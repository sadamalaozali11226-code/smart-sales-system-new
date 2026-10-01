const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(__dirname));

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

async function supabaseRequest(endpoint, options = {}) {
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/${endpoint}`,
    {
      ...options,
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json",
        ...options.headers
      }
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
        : data
    );
  }

  return data;
}

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

// ===============================
// جلب المنتجات
// ===============================
app.get("/api/products", async (req, res) => {
  try {
    const products = await supabaseRequest(
      "products?select=id,name,price,quantity&order=id.asc"
    );

    res.json(products);
  } catch (error) {
    console.error("GET PRODUCTS ERROR:", error);

    res.status(500).json({
      error: "Failed to fetch products",
      details: error.message
    });
  }
});

// ===============================
// إضافة منتج
// ===============================
app.post("/api/products", async (req, res) => {
  const { name, price, quantity } = req.body;

  if (
    !name ||
    price === undefined ||
    quantity === undefined
  ) {
    return res.status(400).json({
      error: "name, price and quantity are required"
    });
  }

  try {
    const products = await supabaseRequest("products", {
      method: "POST",
      headers: {
        Prefer: "return=representation"
      },
      body: JSON.stringify({
        name: String(name).trim(),
        price: Number(price),
        quantity: Number(quantity)
      })
    });

    res.status(201).json(products[0]);

  } catch (error) {
    console.error("CREATE PRODUCT ERROR:", error);

    res.status(500).json({
      error: "Failed to create product",
      details: error.message
    });
  }
});

// ===============================
// تسجيل البيع
// ===============================
app.post("/api/sell", async (req, res) => {

  console.log("SELL REQUEST RECEIVED:", req.body);

  const id = Number(req.body.id);

  if (!Number.isInteger(id)) {
    return res.status(400).json({
      error: "Invalid product id"
    });
  }

  try {

    // جلب المنتج الحالي
    const currentProducts = await supabaseRequest(
      `products?id=eq.${id}&select=id,name,price,quantity`
    );

    if (
      !currentProducts ||
      currentProducts.length === 0
    ) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    const product = currentProducts[0];

    const currentQuantity = Number(product.quantity);

    if (currentQuantity <= 0) {
      return res.status(400).json({
        error: "Product is out of stock"
      });
    }

    const newQuantity = currentQuantity - 1;

    console.log("SELL UPDATE:", {
      id,
      currentQuantity,
      newQuantity
    });

    // تحديث المخزون
    const updatedProducts = await supabaseRequest(
      `products?id=eq.${id}`,
      {
        method: "PATCH",
        headers: {
          Prefer: "return=representation"
        },
        body: JSON.stringify({
          quantity: newQuantity
        })
      }
    );

    if (
      !updatedProducts ||
      updatedProducts.length === 0
    ) {
      return res.status(500).json({
        error: "Product quantity was not updated"
      });
    }

    const updatedProduct = updatedProducts[0];

    console.log("SELL SUCCESS:", {
      id,
      quantity: updatedProduct.quantity
    });

    res.json({
      success: true,
      product: updatedProduct,
      soldQuantity: 1,
      total: Number(product.price)
    });

  } catch (error) {

    console.error("SELL ERROR:", error);

    res.status(500).json({
      error: "Failed to record sale",
      details: error.message
    });
  }
});

// ===============================
// تعديل كمية المنتج
// ===============================
app.put("/api/products/:id", async (req, res) => {

  console.log("PUT PRODUCT RECEIVED:", {
    id: req.params.id,
    body: req.body
  });

  const id = Number(req.params.id);
  const { quantity } = req.body;

  if (!Number.isInteger(id)) {
    return res.status(400).json({
      error: "Invalid product id"
    });
  }

  if (quantity === undefined) {
    return res.status(400).json({
      error: "quantity is required"
    });
  }

  const newQuantity = Number(quantity);

  if (
    !Number.isFinite(newQuantity) ||
    newQuantity < 0
  ) {
    return res.status(400).json({
      error: "Invalid quantity"
    });
  }

  try {

    const updatedProducts = await supabaseRequest(
      `products?id=eq.${id}`,
      {
        method: "PATCH",
        headers: {
          Prefer: "return=representation"
        },
        body: JSON.stringify({
          quantity: newQuantity
        })
      }
    );

    if (
      !updatedProducts ||
      updatedProducts.length === 0
    ) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    res.json(updatedProducts[0]);

  } catch (error) {

    console.error("UPDATE PRODUCT ERROR:", error);

    res.status(500).json({
      error: "Failed to update product",
      details: error.message
    });
  }
});

// ===============================
// تشغيل السيرفر
// ===============================
app.listen(PORT, "0.0.0.0", () => {
  console.log(
    `Server running on port ${PORT}`
  );
});
