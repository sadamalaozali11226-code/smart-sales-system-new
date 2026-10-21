# Sale idempotency rollout and recovery runbook

## Scope

This runbook covers the additive sale-idempotency migration
`supabase/migrations/20261021100000_add_sale_idempotency.sql` and matching
frontend changes. It is not authorization to change production. Run database steps
against a disposable/local or explicitly approved staging project first.

## Preconditions

- [ ] Confirm the target project/ref and environment before executing SQL.
- [ ] Verify a recent, restorable backup exists and identify the restore owner.
- [ ] Confirm the underlying `private.create_sale_transaction(uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)`
      exists, is `SECURITY DEFINER`, and has an empty pinned `search_path`.
- [ ] Review the migration and current schema diff; stop if the preflight fails.
- [ ] Run CI PostgreSQL migration tests and disposable local Supabase tests on the
      exact candidate commit.
- [ ] Exercise the acceptance cases below in staging with non-production data.

## Safe rollout order

1. Deploy the additive database migration to staging first. It adds the idempotency
   table/helper and new named-argument RPC overload while retaining the legacy
   overload for already-open/older clients.
2. Verify migration history, function signatures, grants, RLS, and PostgREST schema
   reload. Do not grant client roles direct access to the idempotency table.
3. Deploy the matching frontend/API commit to staging.
4. Run acceptance tests and inspect sale rows, invoice records, stock movements,
   audit records, and idempotency rows for each case.
5. Observe staging for authorization errors, RPC resolution errors, duplicate sales,
   and invoice/stock inconsistencies before considering production.
6. For production, obtain explicit release approval, confirm backup/restore
   readiness, apply the database migration, then deploy the matching frontend. Keep
   the old RPC overload until old clients are retired and a cleanup migration is
   separately reviewed and approved.

## Schema drift note

A read-only comparison of the live production function with the checked-in historical
migration `20261006202000_harden_sales_numbering_and_payments.sql` found a body-level
difference: the live function handles `store_products.cost_known` when recording
cost totals, while the historical migration body does not. The idempotency candidate
does not replace the underlying sale function, and its preflight checks signature,
`SECURITY DEFINER`, and pinned `search_path`; nevertheless, the repository-based
business integration test cannot prove every detail of the live function body.
Keep staging acceptance as a release gate and do not rewrite the historical migration
as a shortcut.

## Required acceptance tests

- [ ] A normal sale produces exactly one sale, expected invoice, and correct stock
      movement/audit effects.
- [ ] Repeating an identical request with the same key returns the original response
      and creates no additional sale or stock movement.
- [ ] Two concurrent identical requests with the same key produce one sale and the
      same response.
- [ ] Reusing a key with a different payload is rejected without creating another sale.
- [ ] Different keys create separate sales.
- [ ] Unauthenticated users and authenticated users without store membership or
      `sales.create` permission cannot create a sale.
- [ ] Existing clients calling the legacy RPC still work during the rollout window.
- [ ] If a response is lost after commit, retrying the same key returns the original
      result; the UI does not tell the operator to blindly create a second sale.
- [ ] If the result remains uncertain, instructions require checking invoice/sale
      history before starting a different sale.
- [ ] Reapplying the migration preserves existing idempotency rows and responses.
- [ ] Product list, sales list, history, and invoice display refresh independently
      after a committed sale; UI refresh errors do not misreport the sale as failed.

## Recovery and rollback

- Never delete rows from `private.sale_idempotency_requests` as a routine rollback:
  they are durable retry records and deleting them can permit duplicate sales.
- If the frontend causes issues, roll it back to the last known-good deployment
  while leaving additive database objects and stored idempotency records in place.
  The retained legacy RPC supports older clients.
- Do not drop the helper/table or rewrite the original sale function as an emergency
  action. Any schema rollback must be separately reviewed against live data and
  retry history.
- If sale, invoice, stock, or audit records disagree, stop retries for the affected
  operation, preserve logs and request identifiers, reconcile records, and involve
  the system/database owner. Do not issue a compensating sale blindly.
- Restore from backup only under the project's incident procedure and after
  assessing data loss since the backup.

## Current verified state

- CI run #309 passed on candidate commit
  `0318be77747d8512e396fea5d3cd75d849ed7056`: [run #309](https://github.com/sadamalaozali11226-code/smart-sales-system-new/actions/runs/39666429315).
  It tests the checked-in sale transaction implementation end-to-end in isolated
  PostgreSQL: invoice numbering, totals/payment status, stock decrement, inventory
  movements, payment/audit rows, same-key retry, changed-payload rejection,
  insufficient-stock rollback, authorization rejection, concurrent same-key
  requests, incompatible pre-existing table rejection, and migration reapplication
  without data loss.
- Disposable Supabase local run #99 was still running at the last status check:
  [run #99](https://github.com/sadamalaozali11226-code/smart-sales-system-new/actions/runs/39666429370).
  Do not mark it passed until its final conclusion is successful.
- Production migration and production deployment remain unapplied.
