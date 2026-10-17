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
    "20261011221500_guard_supplier_payment_balance_after_returns.sql");
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
  const { getInviteMembershipAction, getAcceptanceAction, isInvitationExpired } =
    await import("../supabase/functions/organization-member-invitations/invitation-state.mjs");

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
});

test("invitation handlers check write failures and never activate a non-invited membership", () => {
  const functionPath = path.join(__dirname, "..", "supabase", "functions",
    "organization-member-invitations", "index.ts");
  const source = fs.readFileSync(functionPath, "utf8");

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
