const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "src", "supabase-client.js"), "utf8");

function configFor(hostname) {
  const window = { location: { hostname } };
  vm.runInNewContext(source, { window, Set, String });
  return window.SmartSalesSupabase;
}

test("only verified production aliases receive production Supabase configuration", () => {
  for (const hostname of [
    "smart-sales-system-new.vercel.app",
    "smart-sales-system-new-my-project-3093.vercel.app",
    "smart-sales-system-new-git-main-my-project-3093.vercel.app"
  ]) {
    const config = configFor(hostname);
    assert.equal(config.url, "https://kpllyyeirhdjwvkrwspg.supabase.co", hostname);
    assert.equal(config.publishableKey, "sb_publishable_OCdRHiaZySGrsgNYV3w0jQ_bWSL1ACV", hostname);
  }
});

test("Vercel preview hosts route to the isolated staging Supabase project", () => {
  for (const hostname of [
    "smart-sales-system-calgv2jmd-my-project-3093.vercel.app",
    "smart-sales-system-new-git-fix-sale-system-mainline-2026-10-22.vercel.app",
    "localhost",
    "127.0.0.1"
  ]) {
    const config = configFor(hostname);
    assert.equal(config.url, "https://jqedxgdstifezjrtgucw.supabase.co", hostname);
    assert.equal(config.publishableKey, "sb_publishable_aCesoZEa-JkUFaNUcX9u3g_jQZcs-jK", hostname);
  }
});

test("alternate hostnames and host casing fail closed to staging, never production", () => {
  for (const hostname of [
    "SMART-SALES-SYSTEM-NEW.VERCEL.APP.attacker.example",
    "smart-sales-system-new.vercel.app.example",
    "",
    "example.com"
  ]) {
    assert.equal(configFor(hostname).url, "https://jqedxgdstifezjrtgucw.supabase.co", hostname);
  }
});
