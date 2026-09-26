const express = require("express");
const path = require("path");
const fs = require("fs");
const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(__dirname));

let products = fs.existsSync("products.json") ? JSON.parse(fs.readFileSync("products.json")) : [];

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

app.get("/api/products", (req, res) => {
  res.json(products);
});

app.post("/api/products", (req, res) => {
  const { name, price, quantity } = req.body;

  if (!name || price === undefined || quantity === undefined) {
    return res.status(400).json({
      error: "name, price and quantity are required",
    });
  }

  const product = {
    id: products.length + 1,
    name,
    price: Number(price),
    quantity: Number(quantity),
  };

  products.push(product);
fs.writeFileSync("products.json", JSON.stringify(products));
  res.status(201).json(product);
});
app.put("/api/products/:id", (req, res) => {
  const id = Number(req.params.id);
  const { quantity } = req.body;

  const product = products.find(p => p.id === id);

  if (!product) {
    return res.status(404).json({
      error: "Product not found"
    });
  }

  product.quantity = Number(quantity);

  fs.writeFileSync("products.json", JSON.stringify(products));

  res.json(product);
});
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server running on port ${PORT}`);
});
