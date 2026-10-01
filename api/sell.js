export default async function handler(req, res) {
  if (req.method !== "POST") {
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

  const id = Number(req.body?.id);

  if (!Number.isInteger(id)) {
    return res.status(400).json({
      error: "Invalid product id"
    });
  }

  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/record_product_sale`,
      {
        method: "POST",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          p_product_id: id
        })
      }
    );

    const text = await response.text();

    let data;

    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = text;
    }

    if (!response.ok) {
      console.error("SUPABASE SALE ERROR:", data);

      const errorMessage =
        typeof data === "object" && data !== null
          ? data.message ||
            data.error ||
            data.hint ||
            JSON.stringify(data)
          : String(data);

      if (
        errorMessage
          .toLowerCase()
          .includes("product not found")
      ) {
        return res.status(404).json({
          error: "Product not found"
        });
      }

      if (
        errorMessage
          .toLowerCase()
          .includes("out of stock")
      ) {
        return res.status(400).json({
          error: "Product is out of stock"
        });
      }

      return res.status(500).json({
        error: "Failed to record sale",
        details: errorMessage
      });
    }

    if (!data || data.success !== true) {
      return res.status(500).json({
        error: "Sale was not recorded correctly"
      });
    }

    return res.status(200).json({
      success: true,
      saleId: data.sale_id,
      invoiceNumber: data.invoice_number,
      product: {
        id: data.product_id,
        name: data.product_name,
        price: Number(data.price),
        quantity: Number(data.quantity)
      },
      soldQuantity: 1,
      total: Number(data.total)
    });

  } catch (error) {
    console.error("SELL ERROR:", error);

    return res.status(500).json({
      error: "Failed to record sale",
      details: error.message
    });
  }
}
