const { after, before, test } = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const net = require("node:net");
const path = require("node:path");

let serverProcess;
let baseUrl;

async function reservePort() {
  const server = net.createServer();
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const { port } = server.address();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}

before(async () => {
  const port = await reservePort();
  baseUrl = `http://127.0.0.1:${port}`;
  serverProcess = spawn(process.execPath, [path.join(__dirname, "..", "server.js")], {
    env: { ...process.env, PORT: String(port) },
    stdio: "ignore",
  });

  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    if (serverProcess.exitCode !== null) {
      throw new Error(`Application server exited with code ${serverProcess.exitCode}`);
    }
    try {
      const response = await fetch(baseUrl);
      if (response.status === 200) return;
    } catch {
      // The listener may not be ready yet.
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error("Application server did not become ready within 8 seconds");
});

after(() => {
  if (serverProcess && serverProcess.exitCode === null) serverProcess.kill("SIGTERM");
});

test("serves the Arabic application and required frontend assets", async () => {
  const home = await fetch(baseUrl);
  assert.equal(home.status, 200);
  assert.match(await home.text(), /نظام المبيعات الذكي/);
  assert.equal(home.headers.get("x-content-type-options"), "nosniff");
  assert.equal(home.headers.get("x-frame-options"), "DENY");

  const report = await fetch(`${baseUrl}/profitability.html`);
  assert.equal(report.status, 200);
  assert.match(await report.text(), /الأرباح والتكاليف/);

  for (const asset of [
    "/src/supabase-client.js",
    "/src/commercial-auth.js",
    "/src/commercial-api.js",
    "/src/member-admin.js",
  ]) {
    const response = await fetch(baseUrl + asset);
    assert.equal(response.status, 200, `Expected asset to be served: ${asset}`);
    assert.match(response.headers.get("content-type") || "", /javascript|ecmascript/i);
  }
});

test("keeps legacy business API disabled", async () => {
  for (const method of ["GET", "POST", "PUT", "DELETE"]) {
    const response = await fetch(`${baseUrl}/api/products`, { method });
    assert.equal(response.status, 410, `${method} /api/products must remain disabled`);
    const body = await response.json();
    assert.equal(body.error, "Legacy API disabled");
  }
});

test("does not expose repository data, migrations, or backend source files", async () => {
  for (const route of [
    "/products.json",
    "/backend/products.json",
    "/backend/server.js",
    "/supabase/migrations/20261009205628_prevent_hard_delete_supplier_purchase_financial_records.sql",
    "/package.json",
    "/vercel.json",
  ]) {
    const response = await fetch(baseUrl + route);
    assert.equal(response.status, 404, `Expected private/non-public path to be hidden: ${route}`);
  }
});
