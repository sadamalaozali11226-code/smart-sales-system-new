# Repair Completion Report — 2026-10-23

## Scope and safety boundary

This report describes the isolated repair branch and staging validation. Production code has not been deployed and PR #51 remains open as a Draft. One narrowly scoped production privilege migration (`20261023143947_revoke_client_truncate_public`) was applied after isolated CI validation; no application code was deployed, and the other candidate migrations remain unapplied to production. One deterministic historical test-return line was reconciled as documented below.

## Code changes prepared in PR #51

- Idempotent sale creation: retries with the same request key do not create duplicate sales; reusing a key with a changed payload is rejected.
- Product/customer queries are scoped to the active organization.
- Supplier-payment submission validates allocation totals before sending.
- Sale-return UI distributes refunds to return lines and verifies that line allocations equal the header refund.
- Database-level guard rejects sale-return RPC calls when line refund allocations do not equal the requested refund.
- Post-commit UI refresh failures no longer report a committed financial operation as failed.
- Supabase client routing uses production only on explicitly enumerated production hostnames; preview/local/alternate hosts route to staging.
- Client TRUNCATE grants are revoked for existing application tables and default privileges are narrowed for future public tables created by the normal `postgres` migration role.
- Runbooks and acceptance documentation distinguish CI/migration tests from full production acceptance.

## Staging baseline and verification

A structure-only snapshot was derived from the live production catalog and applied to the existing staging project. No production business rows were copied.

Verified table names match between production and staging for all 31 public application tables. The candidate changes add the private idempotency table and its functions/constraints/index, update the return RPC invariant, and add three hard-delete triggers for purchase returns, return lines, and supplier refunds. Catalog counts:

| Object | Production | Staging |
|---|---:|---:|
| Public/private columns | 261 | 267 |
| Constraints | 153 | 154 |
| Indexes | 121 | 122 |
| Functions/procedures | 110 | 112 |
| RLS policies | 31 | 31 |
| Non-internal triggers | 4 | 7 |

All 31 staging RLS policies match the production policy definitions exactly. All public application tables have RLS enabled. Staging contains no production business data. A disposable staging table confirmed that anonymous/authenticated roles cannot TRUNCATE a new public table created by the normal `postgres` migration role. During the final verification pass, the staging default ACL for `postgres` was explicitly narrowed again with `ALTER DEFAULT PRIVILEGES ... REVOKE TRUNCATE`; a newly created public probe table returned `has_table_privilege(..., 'TRUNCATE') = false` for both `anon` and `authenticated`, and the probe table was then dropped. ACL expansion confirmed that the `postgres` default ACL no longer grants TRUNCATE to either client role.

The staging catalog also contains platform-managed default privileges for `supabase_admin` in `public` that include TRUNCATE for client roles. The connected SQL session cannot manage that role's default ACL through the normal migration role, and no unsupported role escalation was attempted. This remains a release security blocker until the supported administrative path is confirmed. Existing application tables were checked separately and client roles do not have TRUNCATE on them.

## Tests

- GitHub CI passed on code head `abf10bb88a675856493211435c41f8438572eb21` ([CI run](https://github.com/sadamalaozali11226-code/smart-sales-system-new/actions/runs/39971662246)), including the expanded 31-table TRUNCATE migration regression and the production-aligned migration filename.
- The disposable local Supabase sale-migration workflow passed its migration assertions on the same code head ([local Supabase run](https://github.com/sadamalaozali11226-code/smart-sales-system-new/actions/runs/39971662102)).
- Vercel Preview was READY at `smart-sales-system-e1hr3vabs-my-project-3093.vercel.app` on code head `abf10bb88a675856493211435c41f8438572eb21`.
- Live preview HTTP smoke checks on that deployment: homepage returned 200; `/src/supabase-client.js` returned 200 and selected the staging project for the preview hostname; legacy `/api/products` returned 410 with the expected “Legacy API disabled” response. This verifies routing and the retired legacy endpoint only, not authenticated browser acceptance.
- Staging SQL acceptance passed for sale idempotency (identical retry, changed-payload rejection, distinct request key, stock/audit invariants); valid/mismatched sale returns; paid sale cancellation with one refund and stock restoration; customer payment allocation and atomic overpayment rejection; supplier payment allocation and atomic incomplete-allocation rejection; tenant RLS isolation; current/future client TRUNCATE restrictions for the normal migration role; and hard-delete rejection across seven supplier purchase/return financial tables. All synthetic fixture writes were rolled back.
- A new migration adds database hard-delete guards to `purchase_returns`, `purchase_return_items`, and `supplier_refunds`, reusing the existing guard function. Staging acceptance confirmed all seven purchase/payment/return/refund tables reject hard deletion.
- These results do not replace full authenticated browser-based end-to-end acceptance across all modules. No test user credentials were available in this workflow, so no production account was used or modified.

## Deterministic historical correction

Production sale return `id=1` was a clearly marked test transaction: sale `22`, reference `TEST-RETURN-001`, one returned unit at `120.00`, and a matching cash refund header of `120.00`. Its only return line incorrectly stored `refund_amount=0`. The line was updated to `120.00` under guarded preconditions, and an audit log entry (`financial.reconciliation`) records the source values and basis. Post-check confirmed line total and refund header both equal `120.00`.

No other historical financial rows were altered.

## Remaining release blockers

1. **Migration provenance:** production has 58 migration-history rows while the current branch contains 43 SQL migration files (including candidate migrations). Names/versions differ and some historical source migrations are unavailable. The snapshot makes staging structurally useful, but it does not reconstruct the missing historical migration provenance. Do not mark the production migration history as repaired by fabricating versions.
2. **Three legacy supplier payments are unallocated in the current tables:** IDs 1–3 are `780.00`, `10.00`, and `675.00` (total `1,465.00`). Read-only audit logs strongly link payments 1+2 to deleted receipt 1 (historical total `790.00`) and payment 3 to deleted receipt 2 (historical total `675.00`); receipt 3 (total `448.00`) was recorded as cancelled and unpaid. But receipt headers, line items, and allocation rows for IDs 1–3 are missing, and no retained purchase inventory movements provide product/quantity details. Recreating header-only receipts would make purchase details and inventory reporting inconsistent. Recover a source backup or obtain an accounting-approved archival treatment; do not allocate these payments to current receipts 4 or 5.
3. **Platform-managed default ACL:** client TRUNCATE is still present in `supabase_admin`'s default ACL for `public`. The connected migration role cannot change that role's defaults, so this must be resolved through a supported Supabase administrative path before release. Existing tables and defaults for the normal `postgres` migration role were checked separately.
4. **Full application acceptance:** database-level tests cover sales, returns, cancellation, customer collections, supplier payments, and tenant isolation. Still run authenticated browser workflows and complete purchasing/inventory edge cases, permissions, and reporting with representative test accounts before declaring production readiness.

## Release status

- PR #51: open Draft, not merged.
- Production deployment: not changed.
- Production schema: one targeted TRUNCATE-privilege migration applied and verified; other candidate migrations not applied.
- One explicitly identified test-return line was reconciled and audit-logged; supplier payment rows were not changed.
- Staging schema: reconstructed and validated for the current candidate.
- Production readiness: **not yet certified** until migration provenance, the platform-managed default ACL, and the three legacy payments are resolved, and authenticated browser acceptance is complete.
