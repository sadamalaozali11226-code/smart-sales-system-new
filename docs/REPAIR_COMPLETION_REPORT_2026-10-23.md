# Repair Completion Report — 2026-10-23

## Scope and safety boundary

This report describes the isolated repair branch and staging validation. Production code has not been deployed and PR #51 remains open as a Draft. No production schema migration was applied. One deterministic historical test-return line was reconciled as documented below.

## Code changes prepared in PR #51

- Idempotent sale creation: retries with the same request key do not create duplicate sales; reusing a key with a changed payload is rejected.
- Product/customer queries are scoped to the active organization.
- Supplier-payment submission validates allocation totals before sending.
- Sale-return UI distributes refunds to return lines and verifies that line allocations equal the header refund.
- Database-level guard rejects sale-return RPC calls when line refund allocations do not equal the requested refund.
- Post-commit UI refresh failures no longer report a committed financial operation as failed.
- Supabase client routing uses production only on explicitly enumerated production hostnames; preview/local/alternate hosts route to staging.
- Client TRUNCATE grants are revoked for existing application tables and default privileges are narrowed for future public tables.
- Runbooks and acceptance documentation distinguish CI/migration tests from full production acceptance.

## Staging baseline and verification

A structure-only snapshot was derived from the live production catalog and applied to the existing staging project. No production business rows were copied.

Verified table names match between production and staging for all 31 public application tables. The expected additions for the candidate changes are the private idempotency table and associated functions/constraints/index. Catalog counts:

| Object | Production | Staging |
|---|---:|---:|
| Public/private columns | 261 | 267 |
| Constraints | 153 | 154 |
| Indexes | 121 | 122 |
| Functions/procedures | 110 | 112 |
| RLS policies | 31 | 31 |
| Non-internal triggers | 4 | 4 |

All 31 staging RLS policies match the production policy definitions exactly. All public application tables have RLS enabled. Staging contains no production business data. A disposable staging table confirmed that anonymous/authenticated roles cannot TRUNCATE a newly created public table.

## Tests

- GitHub CI: passed on the current PR head.
- Supabase local sale migration test: passed on the current PR head.
- Vercel Preview: READY/success on the current PR head.
- Staging SQL acceptance: passed for sale idempotency (identical retry, changed-payload rejection, distinct request key, stock/audit invariants) and for return refund-allocation rejection/valid return consistency. Test fixtures were rolled back.
- These results do not replace full browser-based end-to-end acceptance across all modules.

## Deterministic historical correction

Production sale return `id=1` was a clearly marked test transaction: sale `22`, reference `TEST-RETURN-001`, one returned unit at `120.00`, and a matching cash refund header of `120.00`. Its only return line incorrectly stored `refund_amount=0`. The line was updated to `120.00` under guarded preconditions, and an audit log entry (`financial.reconciliation`) records the source values and basis. Post-check confirmed line total and refund header both equal `120.00`.

No other historical financial rows were altered.

## Remaining release blockers

1. **Migration provenance:** production has 57 migration-history rows while the current branch contains 42 SQL migration files (including the newly added candidate migrations). Names/versions differ and some historical source migrations are unavailable. The snapshot makes staging structurally useful, but it does not reconstruct the missing historical migration provenance. Do not mark the production migration history as repaired by fabricating versions.
2. **Three legacy supplier payments are unallocated:** IDs 1–3 are `780.00`, `10.00`, and `675.00` (total `1,465.00`). Their allocation total is zero. The only current purchase receipts for this supplier are IDs 4 and 5, fully allocated at `900.00` and `500.00`; there are no receipt rows for IDs 1–3 to attach these payments to. Payment 1's note refers to an earlier purchase, while payments 2–3 have no matching receipt reference. These may be legacy advances, deleted/archived purchases, or migration residue. They must not be allocated to unrelated receipts by inference.
3. **Full application acceptance:** run the complete sales, returns, inventory, purchasing, supplier payments, customer collections, permissions, and reporting workflows on staging with representative test accounts before declaring production readiness.

## Release status

- PR #51: open Draft, not merged.
- Production deployment: not changed.
- Production schema migrations: not applied.
- Staging schema: reconstructed and validated for the current candidate.
- Production readiness: **not yet certified** until migration provenance is resolved and the three legacy payments are reconciled against source documents or explicitly classified as unapplied advances.
