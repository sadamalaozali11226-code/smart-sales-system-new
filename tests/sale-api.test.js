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

test("sale API rejects invalid item discounts before calling the database", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.createSale({
      idempotencyKey: "40000000-0000-4000-8000-000000000007",
      items: [{ product_id: 12, quantity: 1, discount: -1 }]
    }),
    error => error.message.includes("Invalid sale items") && error.definitive === true
  );
  assert.equal(calls.length, 0);
});

test("sale API rejects invalid customer IDs and non-finite or negative amounts before calling the database", async () => {
  const invalidBodies = [
    { customerId: "not-a-number" },
    { discount: -1 },
    { tax: "not-a-number" },
    { paidAmount: -0.01 },
    { paidAmount: Infinity }
  ];

  for (const invalid of invalidBodies) {
    const { api, calls } = loadApi(() => ({ data: null, error: null }));
    await assert.rejects(
      api.createSale({
        idempotencyKey: "40000000-0000-4000-8000-000000000008",
        items: [{ product_id: 12, quantity: 1 }],
        ...invalid
      }),
      error => error.definitive === true
    );
    assert.equal(calls.length, 0, "Invalid sale input must be rejected before RPC");
  }
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
  assert.match(fallback, /PGRST\[1-6\]\[0-9\]\{2\}/);
  assert.doesNotMatch(fallback, /\[0-9A-Z\]\{5\}/);
  assert.match(fallback, /saleId: result\.sale_id == null \? null : Number\(result\.sale_id\)/);
  assert.match(fallback, /At least one purchase receipt allocation is required/);
  assert.match(fallback, /allocatedAmount-amount/);
  assert.match(fallback, /itemRefundTotal-refundAmount/);
});


test("supplier payment API rejects empty allocations before calling the database", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.recordSupplierPayment({ supplierId: 7, amount: 20, allocations: [] }),
    /At least one purchase receipt allocation is required/
  );
  assert.equal(calls.length, 0);
});

test("supplier payment API rejects allocations that do not equal the payment amount", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.recordSupplierPayment({
      supplierId: 7,
      amount: 20,
      allocations: [{ purchase_receipt_id: 41, amount: 19.99 }]
    }),
    /must equal the total allocated amount/
  );
  assert.equal(calls.length, 0);
});

test("supplier payment API allows exact allocation totals despite floating point addition", async () => {
  const { api, calls } = loadApi(() => ({ data: { id: 12 }, error: null }));
  const result = await api.recordSupplierPayment({
    supplierId: 7,
    amount: 0.3,
    allocations: [
      { purchase_receipt_id: 41, amount: 0.1 },
      { purchase_receipt_id: 42, amount: 0.2 }
    ]
  });
  assert.equal(result.id, 12);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "record_supplier_payment");
  assert.equal(calls[0].args.p_amount, 0.3);
  assert.deepEqual(JSON.parse(JSON.stringify(calls[0].args.p_allocations)), [
    { purchase_receipt_id: 41, amount: 0.1 },
    { purchase_receipt_id: 42, amount: 0.2 }
  ]);
});


test("sale return API rejects a header refund that differs from item refund allocations", async () => {
  const { api, calls } = loadApi(() => ({ data: null, error: null }));
  await assert.rejects(
    api.returnSale({
      saleId: 41,
      refundAmount: 12,
      items: [{ sale_item_id: 1, quantity: 1, refund_amount: 0 }]
    }),
    /must equal the total item refund allocation/
  );
  assert.equal(calls.length, 0);
});

test("sale return API forwards matching header and item refund allocations", async () => {
  const { api, calls } = loadApi(() => ({ data: { id: 5 }, error: null }));
  const result = await api.returnSale({
    saleId: 41,
    refundAmount: 12.01,
    items: [{ sale_item_id: 1, quantity: 1, refund_amount: 12.01 }]
  });
  assert.equal(result.id, 5);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "return_sale_items");
  assert.equal(calls[0].args.p_refund_amount, 12.01);
  assert.equal(calls[0].args.p_items[0].refund_amount, 12.01);
});
