(function () {
  "use strict";

  function client() {
    if (!window.SmartSalesAuth) throw new Error("Authentication is not ready.");
    return window.SmartSalesAuth.getClient();
  }

  function context() {
    const value = window.SmartSalesAuth.getContext();
    if (!value || !value.organization || !value.store) {
      throw new Error("Organization and store context are required.");
    }
    return value;
  }

  async function products() {
    const supabase = client();
    const { store } = context();
    const [p, sp] = await Promise.all([
      supabase.from("products").select("id,name,price,organization_id").order("id"),
      supabase.from("store_products").select("product_id,quantity,reorder_level,average_cost").eq("store_id", store.id)
    ]);
    if (p.error) throw p.error;
    if (sp.error) throw sp.error;
    const map = new Map((sp.data || []).map(x => [Number(x.product_id), x]));
    return (p.data || []).map(x => ({
      id: Number(x.id), name: x.name, price: Number(x.price || 0),
      quantity: Number(map.get(Number(x.id))?.quantity || 0),
      organization_id: x.organization_id
    }));
  }

  async function customers() {
    const { data, error } = await client().from("customers")
      .select("id,name,phone,address,notes,created_at").order("id");
    if (error) throw error;
    return data || [];
  }

  async function sales() {
    const { store } = context();
    const { data, error } = await client().from("sales")
      .select("id,invoice_number,customer_id,subtotal,discount,tax,total,payment_status,status,notes,created_at")
      .eq("store_id", store.id).order("created_at", { ascending: false });
    if (error) throw error;
    return data || [];
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
    const productId = Number(body.id);
    const { data: product, error: productError } = await client()
      .from("products").select("id,name,price").eq("id", productId).maybeSingle();
    if (productError) throw productError;
    if (!product) throw new Error("Product not found.");

    const invoice = "INV-" + Date.now() + "-" + Math.floor(Math.random() * 1000);
    const { data, error } = await client().rpc("create_sale_transaction", {
      p_invoice_number: invoice,
      p_customer_id: body.customerId == null || body.customerId === "" ? null : Number(body.customerId),
      p_items: [{ product_id: productId, quantity: 1, discount: 0 }],
      p_discount: 0,
      p_tax: 0,
      p_paid_amount: Number(body.paidAmount || 0),
      p_payment_method: body.paymentMethod ? String(body.paymentMethod) : "cash",
      p_reference: body.reference ? String(body.reference) : null,
      p_notes: null,
      p_organization_id: organization.id,
      p_store_id: store.id
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

  window.SmartSalesAPI = Object.freeze({
    products, customers, sales, createProduct, createCustomer, updateCustomer, createSale, payment
  });
})();