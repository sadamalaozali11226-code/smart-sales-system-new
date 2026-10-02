export default async function handler(req, res) {
  if (req.method !== "GET") {
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!SUPABASE_URL || !SUPABASE_KEY) {
    return res.status(500).json({
      error: "Supabase environment variables are missing"
    });
  }

  const saleId = Number(req.query?.id);

  if (!Number.isInteger(saleId) || saleId <= 0) {
    return res.status(400).json({
      error: "Invalid sale id"
    });
  }

  const headers = {
    apikey: SUPABASE_KEY,
    Authorization: `Bearer ${SUPABASE_KEY}`,
    "Content-Type": "application/json"
  };

  try {
    // =========================
    // جلب الفاتورة
    // =========================

    const saleResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/sales?id=eq.${saleId}&select=id,invoice_number,customer_id,subtotal,discount,tax,total,payment_status,status,notes,created_at`,
      {
        method: "GET",
        headers
      }
    );

    const saleText = await saleResponse.text();

    let saleData;

    try {
      saleData = saleText ? JSON.parse(saleText) : [];
    } catch {
      saleData = [];
    }

    if (!saleResponse.ok) {
      throw new Error(
        typeof saleData === "object"
          ? JSON.stringify(saleData)
          : saleText
      );
    }

    if (!Array.isArray(saleData) || saleData.length === 0) {
      return res.status(404).json({
        error: "Invoice not found"
      });
    }

    const sale = saleData[0];

    const total = Number(sale.total || 0);

    // =========================
    // جلب أصناف الفاتورة
    // =========================

    const itemsResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/sale_items?sale_id=eq.${saleId}&select=id,product_id,product_name,unit_price,quantity,discount,total&order=id.asc`,
      {
        method: "GET",
        headers
      }
    );

    const itemsText = await itemsResponse.text();

    let itemsData;

    try {
      itemsData = itemsText ? JSON.parse(itemsText) : [];
    } catch {
      itemsData = [];
    }

    if (!itemsResponse.ok) {
      throw new Error(
        typeof itemsData === "object"
          ? JSON.stringify(itemsData)
          : itemsText
      );
    }

    // =========================
    // جلب العميل
    // =========================

    let customer = null;

    if (
      sale.customer_id !== null &&
      sale.customer_id !== undefined
    ) {
      const customerResponse = await fetch(
        `${SUPABASE_URL}/rest/v1/customers?id=eq.${sale.customer_id}&select=id,name,phone,address,notes`,
        {
          method: "GET",
          headers
        }
      );

      const customerText = await customerResponse.text();

      let customerData;

      try {
        customerData = customerText
          ? JSON.parse(customerText)
          : [];
      } catch {
        customerData = [];
      }

      if (!customerResponse.ok) {
        throw new Error(
          typeof customerData === "object"
            ? JSON.stringify(customerData)
            : customerText
        );
      }

      if (
        Array.isArray(customerData) &&
        customerData.length > 0
      ) {
        customer = customerData[0];
      }
    }

    // =========================
    // جلب دفعات الفاتورة
    // =========================

    const paymentsResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/payments?sale_id=eq.${saleId}&select=id,sale_id,amount,payment_method,reference,paid_at&order=paid_at.asc,id.asc`,
      {
        method: "GET",
        headers
      }
    );

    const paymentsText = await paymentsResponse.text();

    let paymentsData;

    try {
      paymentsData = paymentsText
        ? JSON.parse(paymentsText)
        : [];
    } catch {
      paymentsData = [];
    }

    if (!paymentsResponse.ok) {
      throw new Error(
        typeof paymentsData === "object"
          ? JSON.stringify(paymentsData)
          : paymentsText
      );
    }

    if (!Array.isArray(paymentsData)) {
      paymentsData = [];
    }

    // =========================
    // حساب إجمالي المدفوع
    // =========================

    const paidAmount = paymentsData.reduce(
      (sum, payment) =>
        sum + Number(payment.amount || 0),
      0
    );

    const remainingAmount = Math.max(
      total - paidAmount,
      0
    );

    // =========================
    // حالة الدفع الفعلية
    // =========================

    let paymentStatus = sale.payment_status;

    if (remainingAmount <= 0 && total > 0) {
      paymentStatus = "paid";
    } else if (paidAmount > 0) {
      paymentStatus = "partial";
    } else {
      paymentStatus = "unpaid";
    }

    // =========================
    // تجهيز الدفعات
    // =========================

    const payments = paymentsData.map((payment) => ({
      id: Number(payment.id),

      saleId:
        payment.sale_id === null ||
        payment.sale_id === undefined
          ? null
          : Number(payment.sale_id),

      amount: Number(
        payment.amount || 0
      ),

      paymentMethod:
        payment.payment_method || null,

      reference:
        payment.reference || null,

      paidAt:
        payment.paid_at || null
    }));

    // =========================
    // تجهيز الفاتورة
    // =========================

    return res.status(200).json({
      success: true,

      invoice: {
        id: Number(sale.id),

        invoiceNumber:
          sale.invoice_number,

        customerId:
          sale.customer_id === null ||
          sale.customer_id === undefined
            ? null
            : Number(sale.customer_id),

        customer,

        subtotal: Number(
          sale.subtotal || 0
        ),

        discount: Number(
          sale.discount || 0
        ),

        tax: Number(
          sale.tax || 0
        ),

        total,

        // =========================
        // بيانات الدفع
        // =========================

        paymentStatus,

        paidAmount,

        remainingAmount,

        payments,

        status:
          sale.status,

        notes:
          sale.notes || null,

        createdAt:
          sale.created_at,

        // =========================
        // أصناف الفاتورة
        // =========================

        items:
          Array.isArray(itemsData)
            ? itemsData.map((item) => ({
                id:
                  Number(item.id),

                productId:
                  item.product_id === null ||
                  item.product_id === undefined
                    ? null
                    : Number(item.product_id),

                productName:
                  item.product_name,

                unitPrice:
                  Number(
                    item.unit_price || 0
                  ),

                quantity:
                  Number(
                    item.quantity || 0
                  ),

                discount:
                  Number(
                    item.discount || 0
                  ),

                total:
                  Number(
                    item.total || 0
                  )
              }))
            : []
      }
    });

  } catch (error) {
    console.error(
      "INVOICE API ERROR:",
      error
    );

    return res.status(500).json({
      error: "Failed to fetch invoice",
      details: error.message
    });
  }
}
