const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const start = html.indexOf("    async function confirmSale() {");
const end = html.indexOf("    function getSaleById(", start);
assert.notEqual(start, -1, "Expected confirmSale() to exist");
assert.notEqual(end, -1, "Expected confirmSale() boundary to exist");
const confirmSale = html.slice(start, end);

test("sale confirmation blocks concurrent submissions", () => {
  assert.match(confirmSale, /if\s*\(saleSubmissionInProgress\)\s*return/);
  assert.match(html, /let\s+saleSubmissionInProgress\s*=\s*false/);
  assert.ok(
    confirmSale.indexOf("saleSubmissionInProgress = true") < confirmSale.indexOf("await SmartSalesAPI.createSale"),
    "The in-flight guard must be set before the RPC starts"
  );
});

test("a confirmed sale is reported successful before any UI refresh", () => {
  const rpcEnd = confirmSale.indexOf("// The RPC confirmed the sale.");
  const successNotice = confirmSale.indexOf("showMessage(`${t.sold}${invoiceLabel}`)");
  const refresh = confirmSale.indexOf("loadProducts(),");
  assert.ok(rpcEnd >= 0, "Expected a clear post-RPC success boundary");
  assert.ok(successNotice > rpcEnd, "Expected a success notice after the RPC returns");
  assert.ok(refresh > successNotice, "Success must be shown before refreshing UI data");
  assert.match(confirmSale, /const invoiceLabel = data && data\.invoiceNumber/);
});

test("refresh and invoice-display failures cannot be reported as sale-creation failures", () => {
  const refreshStart = confirmSale.indexOf("const refreshResults = await Promise.allSettled([");
  const refreshFailure = confirmSale.indexOf('console.error(\n          "Sale was saved, but one screen refresh failed."');
  const invoiceTry = confirmSale.indexOf("try {\n          await openInvoiceById(data.saleId)");
  const invoiceCatch = confirmSale.indexOf('console.error("Sale was saved, but its invoice could not be opened."');
  assert.ok(refreshStart > 0 && refreshFailure > refreshStart, "Each refresh must be isolated");
  assert.ok(invoiceTry > 0 && invoiceCatch > invoiceTry, "Invoice display must have its own error boundary");
  assert.doesNotMatch(confirmSale.slice(refreshFailure, invoiceTry), /button\.disabled\s*=\s*false/,
    "A post-commit UI failure must not re-enable the sale submission button");
});

test("ambiguous submission errors warn the operator and prevent immediate blind resubmission", () => {
  assert.match(confirmSale, /The sale result could not be confirmed because of a connection error/);
  assert.match(confirmSale, /لا تعاود الإرسال الآن/);
  const ambiguousBranch = confirmSale.slice(
    confirmSale.indexOf("// A lost response is ambiguous"),
    confirmSale.indexOf("return;", confirmSale.indexOf("// A lost response is ambiguous"))
  );
  assert.doesNotMatch(ambiguousBranch, /saleSubmissionInProgress\s*=\s*false/);
  assert.doesNotMatch(ambiguousBranch, /button\.disabled\s*=\s*false/);
});

test("refresh failures are isolated and do not prevent other views from refreshing", () => {
  assert.match(confirmSale, /Promise\.allSettled\(\[/);
  assert.match(confirmSale, /loadProducts\(\),\s*loadSales\(\),\s*loadSalesHistory\(\)/);
  assert.match(confirmSale, /error\.definitive === true/);
});

test("inline scripts still parse after the sale-flow change", () => {
  const inlineScripts = [...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
  assert.ok(inlineScripts.length > 0, "Expected inline scripts in index.html");
  inlineScripts.forEach((match, index) => {
    if (!match[1].trim()) return;
    assert.doesNotThrow(
      () => new vm.Script(match[1], { filename: `index.html#inline-${index + 1}` }),
      `JavaScript syntax error in inline script ${index + 1}`
    );
  });
});
