
const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.get("/", (req, res) => {
  res.json({
    success: true,
    message: "Smart Sales System is running"
  });
});

app.get("/api/test", (req, res) => {
  res.json({
    success: true,
    message: "API works correctly"
  });
});

app.listen(PORT, () => {
  console.log(`Smart Sales System running on port ${PORT}`);
});
