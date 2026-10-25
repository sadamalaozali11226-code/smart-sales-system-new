const { after, before, test } = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const net = require("node:net");
const path = require("node:path");
const fs = require("node:fs");
const vm = require("node:vm");

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

test("exports every browser API method used by the UI, including purchase returns", () => {
  const root = path.join(__dirname, "..");
  const apiSource = fs.readFileSync(path.join(root, "src", "commercial-api.js"), "utf8");
  const htmlSource = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const exportMatch = apiSource.match(/window\.SmartSalesAPI\s*=\s*Object\.freeze\(\{([\s\S]*?)\}\);/);
  assert.ok(exportMatch, "Expected the production browser API export to exist");

  const exportedMethods = new Set(
    [...exportMatch[1].matchAll(/^\s*([A-Za-z_$][\w$]*)\s*,?\s*$/gm)].map(match => match[1])
  );
  const referencedMethods = new Set(
    [...htmlSource.matchAll(/SmartSalesAPI\.([A-Za-z_$][\w$]*)/g)].map(match => match[1])
  );
  const missingMethods = [...referencedMethods].filter(method => !exportedMethods.has(method));
  assert.deepEqual(missingMethods, [], "Every method called by the UI must be exported");

  assert.match(apiSource, /async function purchaseReturnDetails\(/,
    "Purchase return details must be implemented in the shared API");
  assert.match(exportMatch[1], /^\s*purchaseReturnDetails,?\s*$/m,
    "Purchase return details must be exported");
  assert.match(apiSource, /async function returnPurchase\(/,
    "Purchase return submission must be implemented in the shared API");
  assert.match(exportMatch[1], /^\s*returnPurchase,?\s*$/m,
    "Purchase return submission must be exported");
});

test("purchase return history API and UI are wired for read-only return inspection", () => {
  const root = path.join(__dirname, "..");
  const apiSource = fs.readFileSync(path.join(root, "src", "commercial-api.js"), "utf8");
  const htmlSource = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const exportStart = apiSource.indexOf("window.SmartSalesAPI = Object.freeze({");
  const exportEnd = apiSource.indexOf("\n  });", exportStart);
  assert.notEqual(exportStart, -1, "Expected the production browser API export to exist");
  assert.notEqual(exportEnd, -1, "Expected the production browser API export to end");
  const exportSource = apiSource.slice(exportStart, exportEnd);
  assert.ok(apiSource.includes("async function purchaseReturnHistory("));
  assert.ok(exportSource.includes("purchaseReturnHistory,"));
  assert.ok(apiSource.includes('rpc("purchase_return_history"'));
  assert.ok(apiSource.includes("p_organization_id: organization.id"));
  assert.ok(apiSource.includes("p_store_id: store.id"));
  assert.ok(apiSource.includes("p_purchase_receipt_id: receiptId"));
  assert.ok(htmlSource.includes("async function purchaseReturnHistory("), "The inline fallback API must also implement purchase return history");
  assert.ok(htmlSource.includes("purchaseReturnHistory,"), "The inline fallback API must export purchase return history");
  assert.ok(htmlSource.includes("openPurchaseReturnHistory("));
  assert.ok(htmlSource.includes('id="purchaseReturnHistoryModal"'));
  assert.ok(htmlSource.includes("async function openPurchaseReturnHistory(id)"));
  assert.ok(htmlSource.includes("purchaseReturnHistoryEmpty"));
  assert.ok(htmlSource.includes('escapeHtml(item.productName || "-")'));
});

test("purchase return history calls the scoped RPC and maps its return items", async () => {
  const apiSource = fs.readFileSync(path.join(__dirname, "..", "src", "commercial-api.js"), "utf8");
  const calls = [];
  const fakeHistory = [{
    id: 12, returnNumber: "PR-000012", purchaseReceiptId: 5, total: 30,
    refundAmount: 25, refundPaymentMethod: "cash", refundReference: "RF-12",
    reason: "Damaged goods", notes: null, status: "completed", createdAt: "2026-10-26T10:00:00Z",
    items: [{
      id: 31, purchaseReceiptItemId: 9, productId: 3, productName: "Test Product",
      quantity: 3, unitCost: 10, total: 30
    }]
  }];
  const fakeClient = {
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve({ data: fakeHistory, error: null });
    }
  };
  const window = {
    SmartSalesAuth: {
      getClient: () => fakeClient,
      getContext: () => ({ organization: { id: "org-test" }, store: { id: "store-test" } })
    }
  };
  vm.runInNewContext(apiSource, { window });
  const history = await window.SmartSalesAPI.purchaseReturnHistory(5);

  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "purchase_return_history");
  assert.equal(calls[0].args.p_organization_id, "org-test");
  assert.equal(calls[0].args.p_store_id, "store-test");
  assert.equal(calls[0].args.p_purchase_receipt_id, 5);
  assert.equal(history.length, 1);
  assert.equal(history[0].returnNumber, "PR-000012");
  assert.equal(history[0].total, 30);
  assert.equal(history[0].refundAmount, 25);
  assert.equal(history[0].items.length, 1);
  assert.equal(history[0].items[0].productName, "Test Product");
  assert.equal(history[0].items[0].quantity, 3);
});

test("purchase return history RPC enforces purchase-view permission and organization/store scope", () => {
  const migrationPath = path.join(__dirname, "..", "supabase", "migrations",
    "20261026120000_add_purchase_return_history.sql");
  const migration = fs.readFileSync(migrationPath, "utf8");
  assert.ok(migration.includes("private.purchase_return_history"));
  assert.ok(migration.includes("auth.uid() is null"));
  assert.ok(migration.includes("private.is_org_store_member(p_organization_id, p_store_id)"));
  assert.ok(migration.includes("private.has_org_permission(p_organization_id, 'purchases.view')"));
  assert.ok(migration.includes("organization_id = p_organization_id"));
  assert.ok(migration.includes("store_id = p_store_id"));
  assert.ok(migration.includes("id = p_purchase_receipt_id"));
  assert.ok(migration.includes("revoke execute on function public.purchase_return_history(uuid, uuid, bigint) from public, anon"));
  assert.ok(migration.includes("grant execute on function public.purchase_return_history(uuid, uuid, bigint) to authenticated"));
  const helperMigration = fs.readFileSync(path.join(__dirname, "..", "supabase", "migrations",
    "20261026123000_restrict_purchase_return_history_helper.sql"), "utf8");
  assert.ok(helperMigration.includes("revoke execute on function private.purchase_return_history(uuid, uuid, bigint) from public, anon"));
  assert.ok(helperMigration.includes("grant execute on function private.purchase_return_history(uuid, uuid, bigint) to authenticated"));
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

test("all shipped browser JavaScript parses without syntax errors", () => {
  const root = path.join(__dirname, "..");
  for (const file of [
    "src/supabase-client.js",
    "src/commercial-auth.js",
    "src/commercial-api.js",
    "src/member-admin.js",
  ]) {
    assert.doesNotThrow(
      () => new vm.Script(fs.readFileSync(path.join(root, file), "utf8"), { filename: file }),
      `JavaScript syntax error in ${file}`
    );
  }

  for (const file of ["index.html", "profitability.html"]) {
    const html = fs.readFileSync(path.join(root, file), "utf8");
    const inlineScripts = [...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
    assert.ok(inlineScripts.length > 0, `Expected inline scripts in ${file}`);
    inlineScripts.forEach((match, index) => {
      if (!match[1].trim()) return;
      assert.doesNotThrow(
        () => new vm.Script(match[1], { filename: `${file}#inline-${index + 1}` }),
        `JavaScript syntax error in ${file} inline script ${index + 1}`
      );
    });
  }
});

test("legacy backend entrypoint also hides repository files", async () => {
  const port = await reservePort();
  const url = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, [path.join(__dirname, "..", "backend", "server.js")], {
    env: { ...process.env, PORT: String(port) },
    stdio: "ignore",
  });

  try {
    const deadline = Date.now() + 8000;
    let ready = false;
    while (Date.now() < deadline) {
      if (child.exitCode !== null) {
        throw new Error(`Legacy backend exited with code ${child.exitCode}`);
      }
      try {
        const response = await fetch(url);
        if (response.status === 200) {
          ready = true;
          break;
        }
      } catch {
        // Wait for the listener to start.
      }
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.equal(ready, true, "Legacy backend did not start");

    assert.equal((await fetch(url + "/profitability.html")).status, 200);
    assert.equal((await fetch(url + "/src/commercial-api.js")).status, 200);
    for (const route of ["/products.json", "/package.json", "/backend/server.js", "/supabase/migrations/20261010093246_harden_return_financial_invariants.sql"]) {
      assert.equal((await fetch(url + route)).status, 404, `Unexpected public route: ${route}`);
    }
    const api = await fetch(url + "/api/legacy-smoke");
    assert.equal(api.status, 410);
  } finally {
    if (child.exitCode === null) child.kill("SIGTERM");
  }
});

test("does not treat an unassigned member as authorized for every store", () => {
  const authPath = path.join(__dirname, "..", "src", "commercial-auth.js");
  const authSource = fs.readFileSync(authPath, "utf8");
  const loadContextStart = authSource.indexOf("async function loadContext(");
  const loadContextEnd = authSource.indexOf("\n  async function switchOrganization(", loadContextStart);
  assert.notEqual(loadContextStart, -1, "Expected loadContext() to exist");
  assert.notEqual(loadContextEnd, -1, "Expected loadContext() boundary to exist");

  const loadContextSource = authSource.slice(loadContextStart, loadContextEnd);
  assert.match(loadContextSource, /if\s*\(storeIds\.length\s*===\s*0\)/,
    "A member with no assigned stores must be rejected");
  assert.match(loadContextSource, /storesQuery\s*=\s*storesQuery\.in\(["']id["'],\s*storeIds\)/,
    "The store query must always be restricted to assigned store IDs");
  assert.doesNotMatch(loadContextSource, /if\s*\(storeIds\.length\s*>\s*0\)/,
    "The store restriction must not be conditional on a non-empty assignment");
});

test("shows organization-switch context errors outside the hidden login gate", () => {
  const authPath = path.join(__dirname, "..", "src", "commercial-auth.js");
  const authSource = fs.readFileSync(authPath, "utf8");
  const switchStart = authSource.indexOf("async function switchOrganization(");
  const switchEnd = authSource.indexOf("\n  async function switchStore(", switchStart);
  assert.notEqual(switchStart, -1, "Expected switchOrganization() to exist");
  assert.notEqual(switchEnd, -1, "Expected switchOrganization() boundary to exist");

  const switchSource = authSource.slice(switchStart, switchEnd);
  assert.match(switchSource, /showContextError\(/,
    "Switch failures must be shown in a visible notification");
  assert.match(switchSource, /selector\.value\s*=\s*String\(context\.organization\.id\)/,
    "The organization selector must revert when switching fails");
  assert.match(authSource, /notice\.setAttribute\("role",\s*"alert"\)/,
    "The visible notification must be accessible to assistive technology");
});

test("report authorization migration requires report permission and limits all-store scope", () => {
  const migrationPath = path.join(__dirname, "..", "supabase", "migrations",
    "20261010143537_scope_report_rpcs_to_authorized_stores.sql");
  const migration = fs.readFileSync(migrationPath, "utf8");
  assert.match(migration, /private\.commercial_reports_summary/);
  assert.match(migration, /private\.profitability_summary/);
  assert.equal((migration.match(/raise exception 'Reports permission required'/g) || []).length, 2);
  assert.equal((migration.match(/raise exception 'Organization-wide report access denied'/g) || []).length, 2);
  assert.equal((migration.match(/private\.has_org_permission\(p_organization_id,'reports\.read'\)/g) || []).length, 2);
  assert.equal((migration.match(/private\.has_org_permission\(p_organization_id,'stores\.manage'\)/g) || []).length, 2);
});

test("expense RPC migration grants internal execution and enforces cancellation permission", () => {
  const migrationPath = path.join(__dirname, "..", "supabase", "migrations",
    "20261010143948_fix_expense_rpc_execute_permissions.sql");
  const migration = fs.readFileSync(migrationPath, "utf8");
  assert.match(migration, /private\.cancel_expense/);
  assert.match(migration, /private\.has_org_permission\(p_organization_id,'expenses\.create'\)/);
  assert.match(migration, /grant execute on function private\.create_expense\([^;]+ to authenticated/i);
  assert.match(migration, /grant execute on function private\.cancel_expense\([^;]+ to authenticated/i);
  assert.match(migration, /grant execute on function public\.create_expense\([^;]+ to authenticated/i);
  assert.match(migration, /grant execute on function public\.cancel_expense\([^;]+ to authenticated/i);
});

test("account summary and statement migration grants authenticated helper execution only", () => {
  const migrationPath = path.join(__dirname, "..", "supabase", "migrations",
    "20261010152500_fix_account_summary_helper_execute_permissions.sql");
  const migration = fs.readFileSync(migrationPath, "utf8").toLowerCase();
  const signatures = [
    "customer_account_summary(uuid, uuid)",
    "supplier_account_summary(uuid, uuid)",
    "customer_statement(uuid, bigint, uuid, date, date)",
    "supplier_statement(uuid, bigint, uuid, date, date)"
  ];

  for (const signature of signatures) {
    assert.ok(migration.includes(`revoke execute on function private.${signature} from public, anon`));
    assert.ok(migration.includes(`grant execute on function private.${signature} to authenticated`));
  }
});


test("sales summary excludes cancelled invoices but keeps them in history", () => {
  const apiPath = path.join(__dirname, "..", "src", "commercial-api.js");
  const apiSource = fs.readFileSync(apiPath, "utf8");
  const helperMatch = apiSource.match(/function summarizeSales\(normalizedSales\) \{[\s\S]*?\n  \}/);
  assert.ok(helperMatch, "Expected the pure sales summary helper to exist");
  const summarizeSales = vm.runInNewContext(`(${helperMatch[0]})`);

  const sales = [
    { id: 1, status: "completed", total: 100, paidAmount: 40, remainingAmount: 60 },
    { id: 2, status: "completed", total: 50, paidAmount: 0, remainingAmount: 50 },
    { id: 3, status: "cancelled", total: 200, paidAmount: 100, remainingAmount: 100 },
  ];
  const summary = summarizeSales(sales);

  assert.equal(summary.total, 150);
  assert.equal(summary.paidTotal, 40);
  assert.equal(summary.remainingTotal, 110);
  assert.equal(summary.count, 2);
  assert.equal(summary.sales.length, 3, "Cancelled invoices must remain visible in sales history");

  const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
  assert.match(html, /function summarizeSales\(normalizedSales\)/,
    "The inline fallback must use the same cancelled-invoice summary rule");
  assert.match(html, /return summarizeSales\(normalizedSales\);/);
});

test("supplier payment migration caps allocations at purchase balance after returns and refunds", () => {
  const migrationPath = path.join(__dirname, "..", "supabase", "migrations",
    "20261017204900_guard_supplier_payment_balance_after_returns.sql");
  const migration = fs.readFileSync(migrationPath, "utf8");
  assert.match(migration, /private\.record_supplier_payment\(uuid,uuid,bigint,numeric,text,text,text,jsonb\)'::regprocedure/);
  assert.match(migration, /from public\.purchase_returns pr[\s\S]*pr\.status='completed'/);
  assert.match(migration, /from public\.supplier_refunds sr[\s\S]*join public\.purchase_returns pr on pr\.id=sr\.purchase_return_id/);
  assert.match(migration, /v_net_balance := greatest\(v_receipt\.total - v_return_total \+ v_refund_total, 0\)/);
  assert.match(migration, /if\s+v_existing\s*\+\s*v_alloc\s*>\s*v_net_balance\s+then raise exception/);
  assert.match(migration, /v_status\s*:=\s*case when v_new_allocated\s*>=\s*v_net_balance then 'paid' else 'partial' end/);
  assert.match(migration, /if v_occurrences <> 1 then[\s\S]*raise exception/);
});

test("invitation lifecycle state rules fail closed and permit deliberate re-invitation", async () => {
  const {
    getInviteMembershipAction,
    getAcceptanceAction,
    isInvitationExpired,
    getInvitationDisplayStatus,
  } = await import("../supabase/functions/organization-member-invitations/invitation-state.mjs");

  assert.equal(getInviteMembershipAction(null), "create");
  assert.equal(getInviteMembershipAction("suspended"), "reinvite");
  assert.equal(getInviteMembershipAction("inactive"), "reinvite");
  assert.equal(getInviteMembershipAction("active"), "reject");
  assert.equal(getInviteMembershipAction("invited"), "reinvite", "An orphaned invited membership with no pending invitation must be recoverable");

  assert.equal(getAcceptanceAction("invited"), "activate");
  assert.equal(getAcceptanceAction("active"), "accept");
  assert.equal(getAcceptanceAction("inactive"), "reject");
  assert.equal(getAcceptanceAction("suspended"), "reject");

  assert.equal(isInvitationExpired("2020-01-01T00:00:00.000Z", Date.parse("2021-01-01T00:00:00.000Z")), true);
  assert.equal(isInvitationExpired("2030-01-01T00:00:00.000Z", Date.parse("2029-01-01T00:00:00.000Z")), false);
  assert.equal(isInvitationExpired("not-a-date", Date.now()), true);

  const fixedNow = Date.parse("2026-10-23T00:00:00.000Z");
  assert.equal(
    getInvitationDisplayStatus("pending", "2026-10-15T00:00:00.000Z", "active", fixedNow),
    "accepted",
    "An active member must not still appear to have a pending invitation"
  );
  assert.equal(
    getInvitationDisplayStatus("pending", "2026-10-15T00:00:00.000Z", "invited", fixedNow),
    "expired",
    "An expired invitation for a non-active member must be shown as expired"
  );
  assert.equal(
    getInvitationDisplayStatus("pending", "2026-10-30T00:00:00.000Z", null, fixedNow),
    "pending"
  );
  assert.equal(
    getInvitationDisplayStatus("accepted", "2020-01-01T00:00:00.000Z", "active", fixedNow),
    "accepted",
    "A final invitation state must not be overwritten"
  );
});

test("invitation handlers check write failures and never activate a non-invited membership", () => {
  const functionPath = path.join(__dirname, "..", "supabase", "functions",
    "organization-member-invitations", "index.ts");
  const source = fs.readFileSync(functionPath, "utf8");

  assert.match(source, /\.select\("id,expires_at,auth_user_id,accepted_at"\)/,
    "Pending invitation checks must load expiry and identity data for safe reconciliation");
  assert.match(source, /if \(activeMembership\)[\s\S]*?status: "accepted"/,
    "An invitation linked to an already-active member must be reconciled as accepted");
  assert.match(source, /else if \(isInvitationExpired\(pending\.expires_at\)\)[\s\S]*?status: "expired"/,
    "Expired pending invitations must stop blocking a future invite attempt");
  assert.match(source, /getInvitationDisplayStatus\([\s\S]*?activeUserIds\.has\(invitation\.auth_user_id\)/,
    "The invitation list must derive an accurate display state from membership and expiry");

  assert.match(source, /\.in\("status", \["suspended", "inactive", "invited"\]\)/,
    "Re-invitation must only re-enable a previously suspended or inactive membership");
  assert.match(source, /if \(memberError\) throw memberError/,
    "Membership lookup failures must not be treated as a missing member");
  assert.match(source, /if \(suspendError \|\| !suspended\)/,
    "Revoke must fail if suspending the invited membership fails");
  assert.match(source, /\.eq\("status", "invited"\)[\s\S]*?\.select\("id"\)/,
    "Acceptance must condition activation on the membership still being invited");
  assert.match(source, /getAcceptanceAction\(member\.status\)/,
    "Acceptance must distinguish invited, active, and disabled membership states");
  assert.match(source, /if \(expireError\) throw expireError/,
    "Expiry updates must check database errors");
  const expiryStart = source.indexOf("if (isInvitationExpired(invitation.expires_at))");
  const expiryEnd = source.indexOf("\n    const { data: member, error: memberError } = await admin", expiryStart + 100);
  assert.notEqual(expiryStart, -1, "Expired invitations must have a dedicated state transition");
  assert.notEqual(expiryEnd, -1, "Expected expiry handling to end before normal acceptance lookup");
  const expirySource = source.slice(expiryStart, expiryEnd);
  assert.match(expirySource, /update\(\{ status: "suspended" \}\)/,
    "An expired invitation must not leave its membership stuck in invited state");
  assert.match(expirySource, /Failed to restore invited membership after expiry failure/,
    "Expiry failure must attempt to restore the previous membership state");
  assert.match(source, /Failed to restore pending invitation after acceptance failure/,
    "Acceptance must attempt to restore pending status when activation fails");
});
