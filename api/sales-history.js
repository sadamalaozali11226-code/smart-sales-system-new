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

  const headers = {
    apikey: SUPABASE_KEY,
    Authorization: `Bearer ${SUPABASE_KEY}`,
    "Content-Type": "application/json"
  };

  try {
    // =========================
    // جلب جميع المبيعات
    // =========================

    const salesResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/sales?select=id,invoice_number,customer_id,subtotal,discount,tax,total,payment_status,status,notes,created_at&order=created_at.desc`,
      {
        method: "GET",
        headers
      }
    );

    const salesText = await salesResponse.text();

    let salesData;

    try {
      salesData = salesText
        ? JSON.parse(salesText)
        : [];
    } catch {
      salesData = [];
    }

    if (!salesResponse.ok) {
      throw new Error(
        typeof salesData === "object"
          ? JSON.stringify(salesData)
          : salesText
      );
    }

    if (!Array.isArray(salesData)) {
      salesData = [];
    }

    // =========================
    // جلب جميع بنود المبيعات
    // =========================

    const itemsResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/sale_items?select=id,sale_id,product_id,product_name,unit_price,quantity,discount,total&order=id.asc`,
      {
        method: "GET",
        headers
      }
    );

    const itemsText = await itemsResponse.text();

    let itemsData;

    try {
      itemsData = itemsText
        ? JSON.parse(itemsText)
        : [];
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

    if (!Array.isArray(itemsData)) {
      itemsData = [];
    }

    // =========================
    // جلب العملاء
    // =========================

    const customersResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/customers?select=id,name,phone,address,notes`,
      {
        method: "GET",
        headers
      }
    );

    const customersText =
      await customersResponse.text();

    let customersData;

    try {
      customersData = customersText
        ? JSON.parse(customersText)
        : [];
    } catch {
      customersData = [];
    }

    if (!customersResponse.ok) {
      throw new Error(
        typeof customersData === "object"
          ? JSON.stringify(customersData)
          : customersText
      );
    }

    if (!Array.isArray(customersData)) {
      customersData = [];
    }

    // =========================
    // جلب جميع الدفعات
    // =========================

    const paymentsResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/payments?select=id,sale_id,amount,payment_method,reference,paid_at&order=paid_at.asc,id.asc`,
      {
        method: "GET",
        headers
      }
    );

    const paymentsText =
      await paymentsResponse.text();

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
    // إنشاء خريطة العملاء
    // =========================

    const customersMap = new Map();

    for (const customer of customersData) {
      customersMap.set(
        Number(customer.id),
        customer
      );
    }

    // =========================
    // إنشاء خريطة الأصناف
    // =========================

    const itemsMap = new Map();

    for (const item of itemsData) {
      const saleId = Number(item.sale_id);

      if (!itemsMap.has(saleId)) {
        itemsMap.set(saleId, []);
      }

      itemsMap.get(saleId).push({
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
      });
    }

    // =========================
    // إنشاء خريطة الدفعات
    // =========================

    const paymentsMap = new Map();

    for (const payment of paymentsData) {
      const saleId = Number(
        payment.sale_id
      );

      if (!paymentsMap.has(saleId)) {
        paymentsMap.set(saleId, []);
      }

      paymentsMap.get(saleId).push({
        id:
          Number(payment.id),

        saleId:
          payment.sale_id === null ||
          payment.sale_id === undefined
            ? null
            : Number(payment.sale_id),

        amount:
          Number(
            payment.amount || 0
          ),

        paymentMethod:
          payment.payment_method || null,

        reference:
          payment.reference || null,

        paidAt:
          payment.paid_at || null
      });
    }

    // =========================
    // تجهيز سجل المبيعات
    // =========================

    const sales = salesData.map((sale) => {
      const saleId =
        Number(sale.id);

      const customerId =
        sale.customer_id === null ||
        sale.customer_id === undefined
          ? null
          : Number(sale.customer_id);

      const total =
        Number(sale.total || 0);

      const salePayments =
        paymentsMap.get(saleId) || [];

      // =========================
      // حساب إجمالي المدفوع
      // =========================

      const paidAmount =
        salePayments.reduce(
          (sum, payment) =>
            sum +
            Number(
              payment.amount || 0
            ),
          0
        );

      // =========================
      // حساب المتبقي
      // =========================

      const remainingAmount =
        Math.max(
          total - paidAmount,
          0
        );

      // =========================
      // تحديد حالة الدفع الفعلية
      // =========================

      let paymentStatus =
        sale.payment_status;

      if (
        remainingAmount <= 0 &&
        total > 0
      ) {
        paymentStatus =
          "paid";
      } else if (
        paidAmount > 0
      ) {
        paymentStatus =
          "partial";
      } else {
        paymentStatus =
          "unpaid";
      }

      return {
        id:
          saleId,

        invoiceNumber:
          sale.invoice_number,

        customerId,

        customer:
          customerId === null
            ? null
            : customersMap.get(
                customerId
              ) || null,

        subtotal:
          Number(
            sale.subtotal || 0
          ),

        discount:
          Number(
            sale.discount || 0
          ),

        tax:
          Number(
            sale.tax || 0
          ),

        total,

        // =========================
        // بيانات الدفع
        // =========================

        paymentStatus,

        paidAmount,

        remainingAmount,

        payments:
          salePayments,

        // =========================
        // حالة البيع
        // =========================

        status:
          sale.status,

        notes:
          sale.notes || null,

        createdAt:
          sale.created_at,

        // =========================
        // الأصناف
        // =========================

        items:
          itemsMap.get(
            saleId
          ) || []
      };
    });

    // =========================
    // إجمالي المبيعات
    // =========================

    const total =
      sales.reduce(
        (sum, sale) =>
          sum +
          Number(
            sale.total || 0
          ),
        0
      );

    // =========================
    // إجمالي المدفوع
    // =========================

    const paidTotal =
      sales.reduce(
        (sum, sale) =>
          sum +
          Number(
            sale.paidAmount || 0
          ),
        0
      );

    // =========================
    // إجمالي المتبقي
    // =========================

    const remainingTotal =
      sales.reduce(
        (sum, sale) =>
          sum +
          Number(
            sale.remainingAmount || 0
          ),
        0
      );

    // =========================
    // إرجاع البيانات
    // =========================

    return res.status(200).json({
      success: true,

      total,

      paidTotal,

      remainingTotal,

      count:
        sales.length,

      sales
    });

  } catch (error) {
    console.error(
      "SALES HISTORY API ERROR:",
      error
    );

    return res.status(500).json({
      error:
        "Failed to fetch sales history",

      details:
        error.message
    });
  }
}
