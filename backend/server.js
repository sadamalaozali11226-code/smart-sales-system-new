const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const APP_ROOT = path.resolve(__dirname, "..");
const SRC_ROOT = path.join(APP_ROOT, "src");

app.disable("x-powered-by");

app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  next();
});

function sendAppPage(fileName) {
  return (req, res, next) => {
    res.sendFile(path.join(APP_ROOT, fileName), (error) => {
      if (error) next(error);
    });
  };
}

app.get("/", sendAppPage("index.html"));
app.get("/index.html", sendAppPage("index.html"));
app.get("/profitability.html", sendAppPage("profitability.html"));

// Never expose the repository root, JSON fixtures, migration SQL, or backend source.
app.use("/src", express.static(SRC_ROOT, {
  dotfiles: "deny",
  index: false,
  fallthrough: true,
}));

app.use("/api", (req, res) => {
  res.status(410).json({
    error: "Legacy API disabled",
    message: "Use the authenticated commercial API."
  });
});

app.use((req, res) => {
  res.status(404).type("text/plain").send("Not Found");
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Smart Sales legacy backend server listening on port ${PORT}`);
});
