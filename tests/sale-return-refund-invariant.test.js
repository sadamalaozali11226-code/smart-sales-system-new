"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const migration = fs.readFileSync(
  path.join(__dirname, "..", "supabase", "migrations", "20261023100000_enforce_sale_return_item_refund_total.sql"),
  "utf8"
);

test("sale return RPC enforces header-to-line refund allocation equality in the database", () => {
  assert.match(migration, /CREATE OR REPLACE FUNCTION private\.return_sale_items\(/i);
  assert.match(migration, /sum of item refund allocations must equal refund amount/i);
  assert.match(
    migration,
    /sum\(coalesce\(nullif\(item\.value->>'refund_amount',''\)::numeric,0\)\)/i
  );

  const invariantPosition = migration.toLowerCase().indexOf(
    "sum of item refund allocations must equal refund amount"
  );
  const firstWritePosition = migration.toLowerCase().indexOf(
    "insert into public.sale_returns"
  );

  assert.ok(invariantPosition > 0, "database invariant must exist");
  assert.ok(firstWritePosition > invariantPosition, "invariant must run before return records are written");
});

test("sale return RPC retains authenticated security-definer execution and pinned search_path", () => {
  assert.match(migration, /SECURITY DEFINER/i);
  assert.match(migration, /SET search_path TO 'public', 'private'/i);
  assert.match(migration, /notify pgrst, 'reload schema'/i);
});
