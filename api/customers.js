export default async function handler(req, res) {
  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!SUPABASE_URL || !SUPABASE_KEY) {
    return res.status(500).json({
      error: "Supabase environment variables are missing"
    });
  }

  try {
    // GET /api/customers
    if (req.method === "GET") {
      const response = await fetch(
        `${SUPABASE_URL}/rest/v1/customers?select=id,name,phone,address,notes,created_at&order=id.asc`,
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

      return res.status(200).json(data);
    }

    // POST /api/customers
    if (req.method === "POST") {
      const {
        name,
        phone,
        address,
        notes
      } = req.body || {};

      if (!name || !String(name).trim()) {
        return res.status(400).json({
          error: "Customer name is required"
        });
      }

      const response = await fetch(
        `${SUPABASE_URL}/rest/v1/customers`,
        {
          method: "POST",
          headers: {
            apikey: SUPABASE_KEY,
            Authorization: `Bearer ${SUPABASE_KEY}`,
            "Content-Type": "application/json",
            Prefer: "return=representation"
          },
          body: JSON.stringify({
            name: String(name).trim(),
            phone:
              phone === undefined ||
              phone === null
                ? null
                : String(phone).trim(),
            address:
              address === undefined ||
              address === null
                ? null
                : String(address).trim(),
            notes:
              notes === undefined ||
              notes === null
                ? null
                : String(notes).trim()
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
        throw new Error(
          typeof data === "object"
            ? JSON.stringify(data)
            : text
        );
      }

      return res.status(201).json({
        success: true,
        customer: Array.isArray(data)
          ? data[0]
          : data
      });
    }

    // PUT /api/customers?id=1
    if (req.method === "PUT") {
      const id = Number(req.query?.id);

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          error: "Invalid customer id"
        });
      }

      const {
        name,
        phone,
        address,
        notes
      } = req.body || {};

      if (!name || !String(name).trim()) {
        return res.status(400).json({
          error: "Customer name is required"
        });
      }

      const response = await fetch(
        `${SUPABASE_URL}/rest/v1/customers?id=eq.${id}`,
        {
          method: "PATCH",
          headers: {
            apikey: SUPABASE_KEY,
            Authorization: `Bearer ${SUPABASE_KEY}`,
            "Content-Type": "application/json",
            Prefer: "return=representation"
          },
          body: JSON.stringify({
            name: String(name).trim(),
            phone:
              phone === undefined ||
              phone === null
                ? null
                : String(phone).trim(),
            address:
              address === undefined ||
              address === null
                ? null
                : String(address).trim(),
            notes:
              notes === undefined ||
              notes === null
                ? null
                : String(notes).trim()
          })
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
          error: "Customer not found"
        });
      }

      return res.status(200).json({
        success: true,
        customer: data[0]
      });
    }

    // DELETE /api/customers?id=1
    if (req.method === "DELETE") {
      const id = Number(req.query?.id);

      if (!Number.isInteger(id)) {
        return res.status(400).json({
          error: "Invalid customer id"
        });
      }

      const response = await fetch(
        `${SUPABASE_URL}/rest/v1/customers?id=eq.${id}`,
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
          error: "Customer not found"
        });
      }

      return res.status(200).json({
        success: true,
        customer: data[0]
      });
    }

    return res.status(405).json({
      error: "Method not allowed"
    });

  } catch (error) {
    console.error(
      "CUSTOMERS API ERROR:",
      error
    );

    return res.status(500).json({
      error: "Failed to process customers request",
      details: error.message
    });
  }
}
