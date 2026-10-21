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
  await assert.rejects(
    api.createSale({ items: [] }),
    error => error.message.includes("At least one sale item is required") && error.definitive === true
  );
  assert.equal(calls.length, 0);
});

test("sale API rejects invalid quantities before calling the database", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.createSale({ items: [{ product_id: 12, quantity: 0 }] }),
    error => error.message.includes("Invalid sale items") && error.definitive === true
  );
  assert.equal(calls.length, 0);
});

test("sale API forwards a valid sale to the atomic database RPC and returns its identifiers", async () => {
  const { api, calls } = loadApi(() => ({
    data: { sale_id: 41, invoice_number: "INV-000041", total: 24 },
    error: null
  }));
  const result = await api.createSale({
    idempotencyKey: "40000000-0000-4000-8000-000000000001",
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
  assert.equal(calls[0].args.p_idempotency_key, "40000000-0000-4000-8000-000000000001");
  assert.equal(result.saleId, 41);
  assert.equal(result.invoiceNumber, "INV-000041");
});


test("sale API requires a UUID idempotency key before calling the database", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.createSale({ items: [{ product_id: 12, quantity: 1 }] }),
    error => error.message.includes("idempotency key is required") && error.definitive === true
  );
  assert.equal(calls.length, 0);
});

test("sale API propagates a database RPC failure instead of reporting success", async () => {
  const expectedError = new Error("insufficient stock");
  const { api, calls } = loadApi(() => ({ data: null, error: expectedError }));
  await assert.rejects(api.createSale({
    idempotencyKey: "40000000-0000-4000-8000-000000000002",
    items: [{ product_id: 12, quantity: 2 }]
  }), /insufficient stock/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "create_sale_transaction");
});

test("structured database rejections are definitive so the UI can safely release a pending key", async () => {
  const { api } = loadApi(() => ({
    data: null,
    error: { code: "P0001", message: "insufficient stock", details: null, hint: null }
  }));
  await assert.rejects(
    api.createSale({
      idempotencyKey: "40000000-0000-4000-8000-000000000003",
      items: [{ product_id: 12, quantity: 2 }]
    }),
    error => error.message === "insufficient stock" && error.code === "P0001" && error.definitive === true
  );
});

test("transport error codes remain ambiguous", async () => {
  const { api } = loadApi(() => ({
    data: null,
    error: Object.assign(new Error("connection reset"), { code: "ECONNRESET" })
  }));
  await assert.rejects(
    api.createSale({
      idempotencyKey: "40000000-0000-4000-8000-000000000005",
      items: [{ product_id: 12, quantity: 2 }]
    }),
    error => error.message === "connection reset" && error.definitive === false
  );
});

test("connection and unknown-transaction SQLSTATEs remain ambiguous", async () => {
  for (const code of ["08006", "40003", "PGRST003"]) {
    const { api } = loadApi(() => ({
      data: null,
      error: Object.assign(new Error("database connection outcome is uncertain"), { code })
    }));
    await assert.rejects(
      api.createSale({
        idempotencyKey: "40000000-0000-4000-8000-000000000006",
        items: [{ product_id: 12, quantity: 2 }]
      }),
      error => error.code === code && error.definitive === false
    );
  }
});

test("errors without a server error code remain ambiguous", async () => {
  const { api } = loadApi(() => ({
    data: null,
    error: new Error("Failed to fetch")
  }));
  await assert.rejects(
    api.createSale({
      idempotencyKey: "40000000-0000-4000-8000-000000000004",
      items: [{ product_id: 12, quantity: 2 }]
    }),
    error => error.message === "Failed to fetch" && error.definitive === false
  );
});

test("inline deployment fallback keeps the same sale RPC and error propagation contract", () => {
  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
  const fallbackStart = html.indexOf("if (!window.SmartSalesAPI)");
  assert.notEqual(fallbackStart, -1, "Expected the inline fallback guard");
  const fallback = html.slice(fallbackStart);
  assert.match(fallback, /async function createSale\(body\)/);
  assert.match(fallback, /rpc\("create_sale_transaction"/);
  assert.match(fallback, /p_idempotency_key: idempotencyKey/);
  assert.match(fallback, /if \(error\) throw error;/);
  assert.match(fallback, /rpcError\.definitive = typeof error\.code === "string" && .*\.test\(error\.code\);/);
  assert.match(fallback, /saleId: result\.sale_id == null \? null : Number\(result\.sale_id\)/);
});
