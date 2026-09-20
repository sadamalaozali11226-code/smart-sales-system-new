ممتاز. هذا هو الملف الصحيح. الآن سنستبدل محتواه بالكامل بإصدار يدعم إضافة المنتجات وعرضها.
الخطوة الآن
احذف كل محتوى server.js، ثم الصق هذا المحتوى كاملًا:
const express = require("express");
const cors = require("cors");
const fs = require("fs");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

const productsFile = path.join(__dirname, "products.json");

app.use(cors());
app.use(express.json());

function readProducts() {
  try {
    const data = fs.readFileSync(productsFile, "utf8");
    return JSON.parse(data);
  } catch (error) {
    return [];
  }
}

function saveProducts(products) {
  fs.writeFileSync(
    productsFile,
    JSON.stringify(products, null, 2),
    "utf8"
  );
}

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "نظام المبيعات الذكي قيد التشغيل"
  });
});

app.get("/api/test", (req, res) => {
  res.json({
    success: true,
    message: "واجهة برمجة التطبيقات تعمل بشكل صحيح"
  });
});

app.get("/api/products", (req, res) => {
  const products = readProducts();

  res.json({
    success: true,
    products
  });
});

app.post("/api/products", (req, res) => {
  const { name, price, quantity } = req.body;

  if (!name || price === undefined || quantity === undefined) {
    return res.status(400).json({
      success: false,
      message: "الاسم والسعر والكمية مطلوبة"
    });
  }

  const products = readProducts();

  const product = {
    id: Date.now(),
    name,
    price: Number(price),
    quantity: Number(quantity)
  };

  products.push(product);
  saveProducts(products);

  res.status(201).json({
    success: true,
    message: "تمت إضافة المنتج بنجاح",
    product
  });
});

app.listen(PORT, () => {
  console.log(`نظام المبيعات الذكي يعمل على المنفذ ${PORT}`);
});
بعد ذلك انزل إلى أسفل الصفحة واضغط Commit changes.
لا تعدّل أي ملف آخر الآن.
بعد الحفظ، أرسل لي النص الذي يظهر لك في GitHub.
