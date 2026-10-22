const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function loadApi() {
  const queries = [];
  const rows = {
    products: [{ id: 1, name: "Org A product", price: 10, organization_id: "org-a" }],
    store_products: [],
    customers: [{ id: 2, name: "Org A customer", organization_id: "org-a" }]
  };
  const supabase = {
    from(table) {
      const query = { table, filters: [], orders: [] };
      queries.push(query);
      const builder = {
        select(columns) { query.columns = columns; return builder; },
        eq(column, value) { query.filters.push([column, value]); return builder; },
        order(column, options) { query.orders.push([column, options]); return builder; },
        then(resolve, reject) {
          return Promise.resolve({ data: rows[table] || [], error: null }).then(resolve, reject);
        }
      };
      return builder;
    }
  };
  const window = {
    SmartSalesAuth: {
      getClient: () => supabase,
      getContext: () => ({
        organization: { id: "org-a" },
        store: { id: "store-a" }
      })
    }
  };
  const source = fs.readFileSync(path.join(__dirname, "..", "src", "commercial-api.js"), "utf8");
  vm.runInNewContext(source, { window, console, Map, Set, Promise, Number, String, Math, Array, Object, Error });
  return { api: window.SmartSalesAPI, queries };
}

test("product list is explicitly scoped to the active organization and active store", async () => {
  const { api, queries } = loadApi();
  await api.products();
  const products = queries.find(query => query.table === "products");
  const storeProducts = queries.find(query => query.table === "store_products");
  assert.ok(products, "products query should run");
  assert.ok(products.filters.some(([column, value]) => column === "organization_id" && value === "org-a"));
  assert.ok(storeProducts.filters.some(([column, value]) => column === "store_id" && value === "store-a"));
});

test("customer list is explicitly scoped to the active organization", async () => {
  const { api, queries } = loadApi();
  await api.customers();
  const customers = queries.find(query => query.table === "customers");
  assert.ok(customers, "customers query should run");
  assert.ok(customers.filters.some(([column, value]) => column === "organization_id" && value === "org-a"));
});
