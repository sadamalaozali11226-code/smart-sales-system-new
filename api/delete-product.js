export default async function handler(req, res) {
  if (req.method !== "DELETE") {
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

  const id = Number(req.query?.id);

  if (!Number.isInteger(id)) {
    return res.status(400).json({
      error: "Invalid product id"
    });
  }

  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/products?id=eq.${id}`,
      {
        method: "DELETE",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "return=representation"
        }
      }
    );

    const text = await response.text();

    let data;

    try {
      data = text ? JSON.parse(text) : [];
    } catch {
      data = [];
    }

    if (!response.ok) {
      throw new Error(
        typeof data === "object"
          ? JSON.stringify(data)
          : text
      );
    }

    if (!Array.isArray(data) || data.length === 0) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    return res.status(200).json({
      success: true,
      product: data[0]
    });

  } catch (error) {
    console.error("DELETE PRODUCT ERROR:", error);

    return res.status(500).json({
      error: "Failed to delete product",
      details: error.message
    });
  }
}
