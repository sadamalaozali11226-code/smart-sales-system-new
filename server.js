const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

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

app.listen(PORT, () => {
  console.log(`نظام المبيعات الذكي يعمل على المنفذ ${PORT}`);
});
