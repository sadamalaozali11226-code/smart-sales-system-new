const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.static(__dirname));

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "index.html"));
});

// Commercial business operations are intentionally handled by the
// authenticated Supabase client/RPC layer. No Service Role key is used
// by this HTTP server, and no legacy /api business endpoints are exposed.

app.use("/api", (req, res) => {
  res.status(410).json({
    error: "Legacy API disabled",
    message: "Use the authenticated commercial API."
  });
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Static application server running on port ${PORT}`);
});
