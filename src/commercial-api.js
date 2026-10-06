(function () {
  "use strict";

  function client() {
    if (!window.SmartSalesAuth) {
      throw new Error("Authentication is not ready.");
    }
    return window.SmartSalesAuth.getClient();
  }

  function context() {
    const value = window.SmartSalesAuth.getContext();
    if (!value || !value.organization || !value.store) {
      throw new Error("Organization and store context are required.");
    }
    return value;
  }

  function normalizeCustomer(value) {
    if (!value) return null;
    return {
      id: Number(value.id),
      name: value.name || "",
      phone: value.phone || null,
      address: value.address || null,
      notes: value.notes || null,
      created_at: value.created_at || null
    };
  }

  function normalizePayment(value) {
    return {
      id: Number(value.id),
      saleId: value.sale_id == null ? null : Number(value.sale_id),
      amount: Number(value.amount || 0),
      paymentMethod: value.payment_method || null,
      reference: value.reference || null,
      paidAt: value.paid_at || null
    };
  }

  function normalizeSaleItem(value) {
    return {
      id: Number(value.id),
      productId: value.product_id == null ? null : Number(value.product_id),
      productName: value.product_name || "",
      unitPrice: Number(value.unit_price || 0),
      quantity: Number(value.quantity || 0),
      discount: Number(value.discount || 0),
      total: Number(value.total || 0)
    };
  }

  function normalizeSale(value, customer, items, payments) {
    const total = Number(value.total || 0);
    const paidAmount = payments.reduce((sum, item) => sum + Number(item.amount || 0), 0);
    const remainingAmount = Math.max(total - paidAmount, 0);
    let paymentStatus = value.payment_status || "unpaid";

    if (remainingAmount <= 0 && total > 0) {
      paymentStatus = "paid";
    } else if (paidAmount > 0) {
      paymentStatus = "partial";
    } else {
      paymentStatus = "unpaid";
    }

    return {
      id: Number(value.id),
      invoiceNumber: value.invoice_number,
      customerId: value.customer_id == null ? null : Number(value.customer_id),
      customer,
      subtotal: Number(value.subtotal || 0),
      discount: Number(value.discount || 0),
      tax: Number(value.tax || 0),
      total,
      paymentStatus,
      paidAmount,
      remainingAmount,
      payments,
      status: value.status,
      notes: value.notes || null,
      createdAt: value.created_at,
      items
    };
  }

  async function products() {
    const supabase = client();
    const { store } = context();

    const [p, sp] = await Promise.all([
      supabase
        .from("products")
        .select("id,name,price,organization_id")
        .order("id"),
      supabase
        .from("store_products")
        .select("product_id,quantity,reorder_level,average_cost")
        .eq("store_id", store.id)
    ]);

    if (p.error) throw p.error;
    if (sp.error) throw sp.error;

    const map = new Map(
      (sp.data || []).map(item => [Number(item.product_id), item])
    );

    return (p.data || []).map(item => ({
      id: Number(item.id),
      name: item.name,
      price: Number(item.price || 0),
      quantity: Number(map.get(Number(item.id))?.quantity || 0),
      organization_id: item.organization_id
    }));
  }

  async function customers() {
    const { data, error } = await client()
      .from("customers")
      .select("id,name,phone,address,notes,created_at")
      .order("id");

    if (error) throw error;
    return (data || []).map(normalizeCustomer);
  }

  async function sales() {
    const { store } = context();
    const supabase = client();

    const { data: salesData, error } = await supabase
      .from("sales")
      .select("id,invoice_number,customer_id,subtotal,discount,tax,total,payment_status,status,notes,created_at")
      .eq("store_id", store.id)
      .order("created_at", { ascending: false });

    if (error) throw error;

    const salesRows = salesData || [];
    if (salesRows.length === 0) {
      return { total: 0, paidTotal: 0, remainingTotal: 0, count: 0, sales: [] };
    }

    const saleIds = salesRows.map(item => Number(item.id));
    const customerIds = [...new Set(
      salesRows
        .map(item => item.customer_id)
        .filter(id => id != null)
        .map(Number)
    )];

    const [paymentsResult, customersResult] = await Promise.all([
      supabase
        .from("payments")
        .select("id,sale_id,amount,payment_method,reference,paid_at")
        .in("sale_id", saleIds)
        .order("paid_at", { ascending: true }),
      customerIds.length
        ? supabase
            .from("customers")
            .select("id,name,phone,address,notes,created_at")
            .in("id", customerIds)
        : Promise.resolve({ data: [], error: null })
    ]);

    if (paymentsResult.error) throw paymentsResult.error;
    if (customersResult.error) throw customersResult.error;

    const paymentMap = new Map();
    (paymentsResult.data || []).forEach(item => {
      const saleId = Number(item.sale_id);
      if (!paymentMap.has(saleId)) paymentMap.set(saleId, []);
      paymentMap.get(saleId).push(normalizePayment(item));
    });

    const customerMap = new Map(
      (customersResult.data || []).map(item => [Number(item.id), normalizeCustomer(item)])
    );

    const normalizedSales = salesRows.map(item => normalizeSale(
      item,
      item.customer_id == null ? null : customerMap.get(Number(item.customer_id)) || null,
      [],
      paymentMap.get(Number(item.id)) || []
    ));

    return {
      total: normalizedSales.reduce((sum, item) => sum + item.total, 0),
      paidTotal: normalizedSales.reduce((sum, item) => sum + item.paidAmount, 0),
      remainingTotal: normalizedSales.reduce((sum, item) => sum + item.remainingAmount, 0),
      count: normalizedSales.length,
      sales: normalizedSales
    };
  }

  async function salesHistory() {
    const supabase = client();
    const summary = await sales();

    if (summary.sales.length === 0) {
      return summary.sales;
    }

    const saleIds = summary.sales.map(item => Number(item.id));
    const { data: itemsData, error } = await supabase
      .from("sale_items")
      .select("id,sale_id,product_id,product_name,unit_price,quantity,discount,total")
      .in("sale_id", saleIds)
      .order("id", { ascending: true });

    if (error) throw error;

    const itemsMap = new Map();
    (itemsData || []).forEach(item => {
      const saleId = Number(item.sale_id);
      if (!itemsMap.has(saleId)) itemsMap.set(saleId, []);
      itemsMap.get(saleId).push(normalizeSaleItem(item));
    });

    return summary.sales.map(item => ({
      ...item,
      items: itemsMap.get(Number(item.id)) || []
    }));
  }

  async function saleInvoice(saleId) {
    const supabase = client();
    const { store } = context();
    const id = Number(saleId);

    if (!Number.isInteger(id) || id <= 0) {
      throw new Error("Invalid sale id");
    }

    const { data: sale, error: saleError } = await supabase
      .from("sales")
      .select("id,invoice_number,customer_id,subtotal,discount,tax,total,payment_status,status,notes,created_at")
      .eq("id", id)
      .eq("store_id", store.id)
      .maybeSingle();

    if (saleError) throw saleError;
    if (!sale) return null;

    const [itemsResult, paymentsResult, customerResult] = await Promise.all([
      supabase
        .from("sale_items")
        .select("id,sale_id,product_id,product_name,unit_price,quantity,discount,total")
        .eq("sale_id", id)
        .order("id", { ascending: true }),
      supabase
        .from("payments")
        .select("id,sale_id,amount,payment_method,reference,paid_at")
        .eq("sale_id", id)
        .order("paid_at", { ascending: true })
        .order("id", { ascending: true }),
      sale.customer_id == null
        ? Promise.resolve({ data: null, error: null })
        : supabase
            .from("customers")
            .select("id,name,phone,address,notes,created_at")
            .eq("id", sale.customer_id)
            .maybeSingle()
    ]);

    if (itemsResult.error) throw itemsResult.error;
    if (paymentsResult.error) throw paymentsResult.error;
    if (customerResult.error) throw customerResult.error;

    const payments = (paymentsResult.data || []).map(normalizePayment);
    const items = (itemsResult.data || []).map(normalizeSaleItem);
    const customer = normalizeCustomer(customerResult.data);

    return normalizeSale(sale, customer, items, payments);
  }

  async function createProduct(body) {
    const { organization, store } = context();
    const { data, error } = await client().rpc("create_product_for_store", {
      p_name: String(body.name || "").trim(),
      p_price: Number(body.price),
      p_initial_quantity: Number(body.quantity || 0),
      p_reorder_level: 0,
      p_notes: null,
      p_organization_id: organization.id,
      p_store_id: store.id
    });

    if (error) throw error;
    return data;
  }

  async function updateProduct(id, body) {
    const { organization, store } = context();
    const { data, error } = await client().rpc("update_product_for_store", {
      p_product_id: Number(id),
      p_name: String(body.name || "").trim(),
      p_price: Number(body.price),
      p_quantity: Number(body.quantity),
      p_organization_id: organization.id,
      p_store_id: store.id
    });
    if (error) throw error;
    return data;
  }

  async function createCustomer(body) {
    const { organization } = context();
    const { data, error } = await client().rpc("create_customer", {
      p_name: String(body.name || "").trim(),
      p_phone: body.phone ? String(body.phone).trim() : null,
      p_address: body.address ? String(body.address).trim() : null,
      p_notes: body.notes ? String(body.notes).trim() : null,
      p_organization_id: organization.id
    });

    if (error) throw error;
    return data;
  }

  async function updateCustomer(id, body) {
    const { organization } = context();
    const { data, error } = await client().rpc("update_customer", {
      p_customer_id: Number(id),
      p_name: String(body.name || "").trim(),
      p_phone: body.phone ? String(body.phone).trim() : null,
      p_address: body.address ? String(body.address).trim() : null,
      p_notes: body.notes ? String(body.notes).trim() : null,
      p_organization_id: organization.id
    });

    if (error) throw error;
    return data;
  }

  async function createSale(body) {
    const { organization, store } = context();
    const items = Array.isArray(body.items) ? body.items : [];
    if (items.length === 0) {
      throw new Error("At least one sale item is required.");
    }

    const normalizedItems = items.map(item => ({
      product_id: Number(item.product_id),
      quantity: Number(item.quantity),
      discount: Number(item.discount || 0)
    }));

    if (normalizedItems.some(item =>
      !Number.isInteger(item.product_id) ||
      item.product_id <= 0 ||
      !Number.isInteger(item.quantity) ||
      item.quantity <= 0
    )) {
      throw new Error("Invalid sale items.");
    }

    const invoice = null; // Invoice number is generated atomically by the database.

    const { data, error } = await client().rpc("create_sale_transaction", {
      p_invoice_number: invoice,
      p_customer_id: body.customerId == null || body.customerId === "" ? null : Number(body.customerId),
      p_items: normalizedItems,
      p_discount: Number(body.discount || 0),
      p_tax: Number(body.tax || 0),
      p_paid_amount: Number(body.paidAmount || 0),
      p_payment_method: body.paymentMethod ? String(body.paymentMethod) : "cash",
      p_reference: body.reference ? String(body.reference) : null,
      p_notes: body.notes ? String(body.notes) : null,
      p_organization_id: organization.id,
      p_store_id: store.id
    });

    if (error) throw error;

    const result = data || {};
    return {
      ...result,
      saleId: result.sale_id == null ? null : Number(result.sale_id),
      invoiceNumber: result.invoice_number || invoice
    };
  }

  async function returnSale(body) {
    const { organization, store } = context();
    const items = Array.isArray(body.items) ? body.items : [];
    if (!items.length) throw new Error("At least one return item is required.");

    const normalizedItems = items.map(item => ({
      sale_item_id: Number(item.sale_item_id),
      quantity: Number(item.quantity),
      refund_amount: Number(item.refund_amount || 0)
    }));

    if (normalizedItems.some(item =>
      !Number.isInteger(item.sale_item_id) || item.sale_item_id <= 0 ||
      !Number.isInteger(item.quantity) || item.quantity <= 0 ||
      !Number.isFinite(item.refund_amount) || item.refund_amount < 0
    )) throw new Error("Invalid sale return items.");

    const { data, error } = await client().rpc("return_sale_items", {
      p_organization_id: organization.id,
      p_store_id: store.id,
      p_sale_id: Number(body.saleId),
      p_items: normalizedItems,
      p_reason: body.reason ? String(body.reason).trim() : null,
      p_notes: body.notes ? String(body.notes).trim() : null,
      p_refund_amount: Number(body.refundAmount || 0),
      p_refund_payment_method: body.refundPaymentMethod ? String(body.refundPaymentMethod) : "cash",
      p_refund_reference: body.refundReference ? String(body.refundReference).trim() : null
    });
    if (error) throw error;
    return data;
  }

  async function cancelSale(body) {
    const { organization } = context();
    const reason = String(body.reason || "").trim();
    if (!reason) throw new Error("Cancellation reason is required.");
    const { data, error } = await client().rpc("cancel_sale", {
      p_organization_id: organization.id,
      p_sale_id: Number(body.saleId),
      p_reason: reason,
      p_refund_payment_method: body.refundPaymentMethod ? String(body.refundPaymentMethod) : "cash",
      p_refund_reference: body.refundReference ? String(body.refundReference).trim() : null
    });
    if (error) throw error;
    return data;
  }

  async function payment(body) {
    const { data, error } = await client().rpc("record_sale_payment", {
      p_sale_id: Number(body.saleId),
      p_amount: Number(body.amount),
      p_payment_method: body.paymentMethod ? String(body.paymentMethod) : "cash",
      p_reference: body.reference ? String(body.reference) : null
    });

    if (error) throw error;
    return data;
  }


  async function suppliers() {
    const { organization } = context();
    const { data, error } = await client().rpc("list_suppliers", {
      p_organization_id: organization.id
    });
    if (error) throw error;
    return data || [];
  }

  async function purchases() {
    const { organization, store } = context();
    const { data, error } = await client().rpc("list_purchase_receipts", {
      p_organization_id: organization.id,
      p_store_id: store.id
    });
    if (error) throw error;
    return data || [];
  }

  async function createSupplier(body) {
    const { organization } = context();
    const { data, error } = await client().rpc("create_supplier", {
      p_organization_id: organization.id,
      p_name: String(body.name || "").trim(),
      p_phone: body.phone ? String(body.phone).trim() : null,
      p_address: body.address ? String(body.address).trim() : null,
      p_tax_number: body.taxNumber ? String(body.taxNumber).trim() : null,
      p_notes: body.notes ? String(body.notes).trim() : null
    });
    if (error) throw error;
    return data;
  }

  async function updateSupplier(id, body) {
    const { organization } = context();
    const { data, error } = await client().rpc("update_supplier", {
      p_organization_id: organization.id,
      p_supplier_id: Number(id),
      p_name: String(body.name || "").trim(),
      p_phone: body.phone ? String(body.phone).trim() : null,
      p_address: body.address ? String(body.address).trim() : null,
      p_tax_number: body.taxNumber ? String(body.taxNumber).trim() : null,
      p_notes: body.notes ? String(body.notes).trim() : null,
      p_status: body.status || "active"
    });
    if (error) throw error;
    return data;
  }

  async function createPurchase(body) {
    const { organization, store } = context();
    const items = Array.isArray(body.items) ? body.items : [];
    if (items.length === 0) throw new Error("At least one purchase item is required.");

    const normalizedItems = items.map(item => ({
      product_id: Number(item.product_id),
      quantity: Number(item.quantity),
      unit_cost: Number(item.unit_cost)
    }));

    if (normalizedItems.some(item =>
      !Number.isInteger(item.product_id) || item.product_id <= 0 ||
      !Number.isInteger(item.quantity) || item.quantity <= 0 ||
      !Number.isFinite(item.unit_cost) || item.unit_cost < 0
    )) {
      throw new Error("Invalid purchase items.");
    }

    const { data, error } = await client().rpc("create_purchase", {
      p_organization_id: organization.id,
      p_store_id: store.id,
      p_supplier_id: Number(body.supplierId),
      p_receipt_number: String(body.supplierInvoiceNumber || "").trim(),
      p_items: normalizedItems,
      p_discount: Number(body.discount || 0),
      p_tax: Number(body.tax || 0),
      p_paid_amount: Number(body.paidAmount || 0),
      p_payment_method: body.paymentMethod ? String(body.paymentMethod) : "cash",
      p_reference: body.reference ? String(body.reference) : null,
      p_due_date: body.dueDate || null,
      p_notes: body.notes ? String(body.notes) : null
    });
    if (error) throw error;
    return data;
  }

  async function cancelPurchase(purchaseReceiptId, reason) {
    const { organization, store } = context();
    const text = String(reason || "").trim();
    if (!text) throw new Error("Cancellation reason is required.");

    const { data, error } = await client().rpc("cancel_purchase", {
      p_organization_id: organization.id,
      p_store_id: store.id,
      p_purchase_receipt_id: Number(purchaseReceiptId),
      p_reason: text
    });
    if (error) throw error;
    return data;
  }

  async function recordSupplierPayment(body) {
    const { organization, store } = context();
    const allocations = Array.isArray(body.allocations) ? body.allocations : [];
    const normalizedAllocations = allocations.map(item => ({
      purchase_receipt_id: Number(item.purchase_receipt_id),
      amount: Number(item.amount)
    }));

    if (normalizedAllocations.some(item =>
      !Number.isInteger(item.purchase_receipt_id) ||
      item.purchase_receipt_id <= 0 ||
      !Number.isFinite(item.amount) ||
      item.amount <= 0
    )) {
      throw new Error("Invalid supplier payment allocations.");
    }

    const { data, error } = await client().rpc("record_supplier_payment", {
      p_organization_id: organization.id,
      p_store_id: store.id,
      p_supplier_id: Number(body.supplierId),
      p_amount: Number(body.amount),
      p_payment_method: body.paymentMethod ? String(body.paymentMethod) : "cash",
      p_reference: body.reference ? String(body.reference) : null,
      p_notes: body.notes ? String(body.notes) : null,
      p_allocations: normalizedAllocations
    });
    if (error) throw error;
    return data;
  }

  window.SmartSalesAPI = Object.freeze({
    products,
    customers,
    sales,
    salesHistory,
    saleInvoice,
    createProduct,
    updateProduct,
    createCustomer,
    updateCustomer,
    createSale,
    payment,
    returnSale,
    cancelSale,
    suppliers,
    createSupplier,
    updateSupplier,
    createPurchase,
    recordSupplierPayment,
    cancelPurchase,
    purchases
  });
})();