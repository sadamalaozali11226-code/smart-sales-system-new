const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function loadApi(rpcImpl) {
  const calls = [];
  const supabase = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      return rpcImpl(name, args);
    }
  };
  const window = {
    SmartSalesAuth: {
      getClient: () => supabase,
      getContext: () => ({
        organization: { id: "org-test" },
        store: { id: "store-test" }
      })
    }
  };
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "commercial-api.js"), "utf8");
  vm.runInNewContext(source, { window, console, Map, Set, Promise, Number, String, Math, Array, Object, Error });
  return { api: window.SmartSalesAPI, calls };
}

test("sale API rejects an empty item list before calling the database", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(api.createSale({ items: [] }), /At least one sale item is required/);
  assert.equal(calls.length, 0);
});

test("sale API rejects invalid quantities before calling the database", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.createSale({ items: [{ product_id: 12, quantity: 0 }] }),
    /Invalid sale items/
  );
  assert.equal(calls.length, 0);
});

test("sale API forwards a valid sale to the atomic database RPC and returns its identifiers", async () => {
  const { api, calls } = loadApi(() => ({
    data: { sale_id: 41, invoice_number: "INV-000041", total: 24 },
    error: null
  }));
  const result = await api.createSale({
    customerId: null,
    items: [{ product_id: 12, quantity: 2, discount: 1 }],
    discount: 0,
    tax: 1,
    paidAmount: 10,
    paymentMethod: "cash",
    reference: "test-ref",
    notes: "isolated unit test"
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "create_sale_transaction");
  assert.deepEqual(JSON.parse(JSON.stringify(calls[0].args.p_items)), [
    { product_id: 12, quantity: 2, discount: 1 }
  ]);
  assert.equal(calls[0].args.p_organization_id, "org-test");
  assert.equal(calls[0].args.p_store_id, "store-test");
  assert.equal(calls[0].args.p_invoice_number, null);
  assert.equal(result.saleId, 41);
  assert.equal(result.invoiceNumber, "INV-000041");
});

test("sale API propagates a database RPC failure instead of reporting success", async () => {
  const expectedError = new Error("insufficient stock");
  const { api, calls } = loadApi(() => ({ data: null, error: expectedError }));
  await assert.rejects(api.createSale({
    items: [{ product_id: 12, quantity: 2 }]
  }), /insufficient stock/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "create_sale_transaction");
});

test("inline deployment fallback keeps the same sale RPC and error propagation contract", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
  const fallbackStart = html.indexOf("if (!window.SmartSalesAPI)");
  assert.notEqual(fallbackStart, -1, "Expected the inline fallback guard");
  const fallback = html.slice(fallbackStart);
  assert.match(fallback, /async function createSale\(body\)/);
  assert.match(fallback, /rpc\("create_sale_transaction"/);
  assert.match(fallback, /if \(error\) throw error;/);
  assert.match(fallback, /saleId: result\.sale_id == null \? null : Number\(result\.sale_id\)/);
});
