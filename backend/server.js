const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const appRoot = path.resolve(__dirname, "..");

app.use(express.json());
app.use(express.static(appRoot, { index: false }));

app.get("/", (req, res) => {
  res.sendFile(path.join(appRoot, "index.html"));
});

// Business operations must go through the authenticated Supabase RPC layer.
// Keep legacy JSON-file endpoints disabled to prevent bypassing authorization.
app.use("/api", (req, res) => {
  res.status(410).json({
    error: "Legacy API disabled",
    message: "Use the authenticated commercial API."
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Static application server running on port ${PORT}`);
});
