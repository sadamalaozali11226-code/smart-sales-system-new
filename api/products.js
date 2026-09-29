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
  try {
    // GET /api/products
    if (req.method === "GET") {
      const products = await supabaseRequest(
        "products?select=id,name,price,quantity&order=id.asc"
      );

      return res.status(200).json(products);
    }

    // POST /api/products
    if (req.method === "POST") {
      const { name, price, quantity } = req.body || {};

      if (!name || price === undefined || quantity === undefined) {
        return res.status(400).json({
          error: "name, price and quantity are required"
        });
      }

      const products = await supabaseRequest("products", {
        method: "POST",
        headers: {
          Prefer: "return=representation"
        },
        body: JSON.stringify({
          name,
          price: Number(price),
          quantity: Number(quantity)
        })
      });

      return res.status(201).json(products[0]);
    }

    return res.status(405).json({
      error: "Method not allowed"
    });
  } catch (error) {
    console.error(error);

    return res.status(500).json({
      error: "Failed to process products request"
    });
  }
};
