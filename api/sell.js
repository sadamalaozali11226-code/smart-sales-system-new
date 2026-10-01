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
    // جلب المنتج الحالي
    const productResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/products?id=eq.${id}&select=id,name,price,quantity`,
      {
        method: "GET",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json"
        }
      }
    );

    const productText = await productResponse.text();

    let products;

    try {
      products = productText
        ? JSON.parse(productText)
        : [];
    } catch {
      products = [];
    }

    if (!productResponse.ok) {
      throw new Error(
        typeof products === "object"
          ? JSON.stringify(products)
          : productText
      );
    }

    if (!products || products.length === 0) {
      return res.status(404).json({
        error: "Product not found"
      });
    }

    const product = products[0];

    const currentQuantity = Number(product.quantity);

    if (
      !Number.isFinite(currentQuantity) ||
      currentQuantity <= 0
    ) {
      return res.status(400).json({
        error: "Product is out of stock"
      });
    }

    const newQuantity = currentQuantity - 1;

    // تحديث كمية المنتج
    const updateResponse = await fetch(
      `${SUPABASE_URL}/rest/v1/products?id=eq.${id}`,
      {
        method: "PATCH",
        headers: {
          apikey: SUPABASE_KEY,
          Authorization: `Bearer ${SUPABASE_KEY}`,
          "Content-Type": "application/json",
          Prefer: "return=representation"
        },
        body: JSON.stringify({
          quantity: newQuantity
        })
      }
    );

    const updateText = await updateResponse.text();

    let updatedProducts;

    try {
      updatedProducts = updateText
        ? JSON.parse(updateText)
        : [];
    } catch {
      updatedProducts = [];
    }

    if (!updateResponse.ok) {
      throw new Error(
        typeof updatedProducts === "object"
          ? JSON.stringify(updatedProducts)
          : updateText
      );
    }

    if (
      !updatedProducts ||
      updatedProducts.length === 0
    ) {
      return res.status(500).json({
        error: "Product quantity was not updated"
      });
    }

    const updatedProduct = updatedProducts[0];

    return res.status(200).json({
      success: true,
      product: updatedProduct,
      soldQuantity: 1,
      total: Number(product.price)
    });

  } catch (error) {
    console.error("SELL ERROR:", error);

    return res.status(500).json({
      error: "Failed to record sale",
      details: error.message
    });
  }
}
