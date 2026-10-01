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

  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/sales?select=total`,
      {
        method: "GET",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json"
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

    const salesTotal = Array.isArray(data)
      ? data.reduce(
          (sum, sale) =>
            sum + Number(sale.total || 0),
          0
        )
      : 0;

    return res.status(200).json({
      success: true,
      total: salesTotal
    });

  } catch (error) {
    console.error("GET SALES ERROR:", error);

    return res.status(500).json({
      error: "Failed to fetch sales",
      details: error.message
    });
  }
}
