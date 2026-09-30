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

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

// جلب المنتجات
app.get("/api/products", async (req, res) => {
  try {
    const products = await supabaseRequest(
      "products?select=id,name,price,quantity&order=id.asc"
    );

    res.json(products);
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: "Failed to fetch products"
    });
  }
});

// إضافة منتج
app.post("/api/products", async (req, res) => {
  const { name, price, quantity } = req.body;

  if (!name || price === undefined || quantity === undefined) {
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
        name,
        price: Number(price),
        quantity: Number(quantity)
      })
    });

    res.status(201).json(products[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: "Failed to create product"
    });
  }
});

// تعديل كمية المنتج + تسجيل البيع
app.put("/api/products/:id", async (req, res) => {
console.log("SALE PUT RECEIVED", {
  id: req.params.id,
  body: req.body
}); 
  const id = Number(req.params.id);
  const { quantity } = req.body;

  if (quantity === undefined) {
    return res.status(400).json({
      error: "quantity is required"
    });
  }

  try {
    // جلب بيانات المنتج الحالية
    const currentProducts = await supabaseRequest(
      `products?id=eq.${id}&select=id,name,price,quantity`
    );

    if (!currentProducts || currentProducts.length === 0) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    const currentProduct = currentProducts[0];
    const currentQuantity = Number(currentProduct.quantity);
    const newQuantity = Number(quantity);

    // إذا نقص المخزون بمقدار 1 فهذا يعني تنفيذ عملية بيع
    if (newQuantity === currentQuantity - 1) {
      const invoiceNumber = `INV-${Date.now()}`;

      const sale = await supabaseRequest("rpc/create_sale", {
        method: "POST",
        body: JSON.stringify({
          p_invoice_number: invoiceNumber,
          p_customer_id: null,
          p_product_id: id,
          p_quantity: 1,
          p_payment_method: "cash"
        })
      });

      // جلب المنتج بعد البيع
      const updatedProducts = await supabaseRequest(
        `products?id=eq.${id}&select=id,name,price,quantity`
      );

      return res.json({
        ...updatedProducts[0],
        sale: sale
      });
    }

    // في حالة تعديل الكمية بطريقة عادية
    const products = await supabaseRequest(`products?id=eq.${id}`, {
      method: "PATCH",
      headers: {
        Prefer: "return=representation"
      },
      body: JSON.stringify({
        quantity: newQuantity
      })
    });

    if (!products || products.length === 0) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    res.json(products[0]);

  } catch (error) {
    console.error(error);

    res.status(500).json({
      error: "Failed to update product",
      details: error.message
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
