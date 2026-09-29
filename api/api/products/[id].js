const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

async function supabaseRequest(endpoint, options = {}) {
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    throw new Error("Missing Supabase environment variables");
  }

  const response = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
    ...options,
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      "Content-Type": "application/json",
      ...options.headers
    }
  });

  const text = await response.text();

  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }

  if (!response.ok) {
    throw new Error(
      typeof data === "object" ? JSON.stringify(data) : data
    );
  }

  return data;
}

module.exports = async (req, res) => {
  if (req.method !== "PUT") {
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  try {
    const id = Number(req.query.id);
    const { quantity } = req.body || {};

    if (!id || quantity === undefined) {
      return res.status(400).json({
        error: "id and quantity are required"
      });
    }

    const products = await supabaseRequest(
      `products?id=eq.${id}`,
      {
        method: "PATCH",
        headers: {
          Prefer: "return=representation"
        },
        body: JSON.stringify({
          quantity: Number(quantity)
        })
      }
    );

    if (!products || products.length === 0) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    return res.status(200).json(products[0]);
  } catch (error) {
    console.error(error);

    return res.status(500).json({
      error: "Failed to update product"
    });
  }
};
