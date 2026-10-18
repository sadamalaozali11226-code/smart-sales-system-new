# Work progress — 2026-10-19

## Actions completed in this session

- Rechecked the current production Supabase role context and confirmed the SQL execution role is `postgres`, which is not a member of `supabase_admin`; `supabase_admin` is platform-managed and has superuser status in the inspected catalog.
- Reconfirmed the production privilege finding: client roles have `TRUNCATE` grants on the 27 listed application tables in `public`; default `TRUNCATE` ACLs also exist for `postgres` and `supabase_admin` in `public`.
- Added candidate migration `supabase/migrations/20261019090000_revoke_client_truncate_public.sql` on the audit branch only. It revokes `TRUNCATE` from `anon` and `authenticated` on the 27 reviewed application tables and removes the corresponding default grant for future `public` tables created by `postgres`.
- Deliberately did not attempt to alter `supabase_admin` default privileges from the application migration, because the inspected execution role lacks membership in that platform-managed role. This remains a release gate requiring an approved supported administrative path; it is not silently treated as fixed.
- Added a disposable PostgreSQL fixture that runs the actual migration file and asserts:
  - `anon` and `authenticated` lose `TRUNCATE` on the reviewed table set;
  - `service_role` retains its `TRUNCATE` grant;
  - existing `SELECT` grants remain unchanged;
  - future `public` tables created by `postgres` do not inherit client `TRUNCATE`.
- Updated CI to execute this actual migration in its isolated PostgreSQL 16 service.
- Updated PR #49 title and description to reflect that the branch now contains a migration candidate and its isolated tests.

## Validation evidence

GitHub Actions run 39175286576 completed successfully for head commit `66478b5fc308814ee40eefc8e2cb47ff1b493825`. The `smoke-tests` job succeeded, including the new step `Test the actual public TRUNCATE migration in isolated PostgreSQL`.

This is isolated database/CI validation only. It is not an end-to-end sales acceptance test and does not establish that every financial workflow is correct.

## Sales path review

- The current browser API sends sale requests to `create_sale_transaction`.
- The inspected production implementation inserts the sale header, inserts sale items, updates `store_products`, writes `inventory_movements`, records any payment, and writes the audit log in one PostgreSQL function invocation. PostgreSQL transaction atomicity means an exception during this invocation should roll back those changes together.
- The current production records inspected earlier show the known sale inventory movement tied to the existing sale record. No orphan sale inventory movement was established in that read-only check.
- The reported symptom (stock reduced but sale absent) is therefore **not reproduced or ruled out**. It requires an isolated end-to-end test of the actual function and frontend behavior. Do not create test transactions in production.

## Production safety

- No production database permissions or schema were changed.
- No financial records were inserted, updated, or deleted.
- No Vercel production deployment was triggered by this work.
- PR #49 remains open and draft; no merge was performed.

## Remaining gates

1. Resolve the `supabase_admin` default ACL through an approved supported path, or explicitly document/accept the remaining future-table risk before release.
2. Complete isolated end-to-end sales tests for cash/partial payment, insufficient stock rollback, duplicate request/retry, partial/full returns, and cancellation; reconcile sale headers, items, payments, inventory, and audit rows.
3. Complete isolated purchase, supplier payment, expense, organization/store isolation, auth/email, and backup/restore acceptance tests.
4. Reconcile the unallocated supplier payments totaling 1465.00 against source records before any accounting changes.
5. Only after review and explicit approval, apply the reviewed privilege migration to production and verify effective privileges with read-only catalog queries.
