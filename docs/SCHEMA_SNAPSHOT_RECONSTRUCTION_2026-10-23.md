# Production schema snapshot and staging reconstruction — 2026-10-23

## Purpose

The repository's historical migration sources are incomplete: production records 57 migration-history entries while the repository currently contains 39 SQL migration files. The missing history must not be replaced with a guessed baseline or by running the available files in sequence against an empty database.

To unblock safe testing, this artifact captures the **current structure** directly from PostgreSQL catalogs in production. It is not a reconstruction of the original migration-by-migration history.

## Artifacts

- `supabase/baselines/production-schema-snapshot-2026-10-23.sql` — schema-only DDL generated from the production catalogs.
- `supabase/baselines/repair-staging-rls-policies-2026-10-23.sql` — staging-only repair script used to align the policies after validating the export. The current snapshot file now contains the correct policy commands.
- `supabase/migrations/20261021100000_add_sale_idempotency.sql` — candidate sale idempotency migration.
- `supabase/migrations/20261023100000_enforce_sale_return_item_refund_total.sql` — database-level guard requiring item refund allocations to sum to the return's refund amount.

## Scope and safeguards

- The snapshot contains DDL, function definitions, policies, grants, constraints, indexes, and triggers for `public` and `private`; it does **not** contain application table rows.
- It is intended only for a confirmed empty, isolated staging database. Do not apply it to a populated database or production.
- Supabase-managed schemas, roles, auth data, storage data, and other platform data are not exported by this artifact.
- The staging project was reconstructed from the snapshot, then the candidate migrations were applied there. The production database was not modified.
- The baseline is intentionally outside `supabase/migrations`: it represents a snapshot of the current state, not a historical migration that should run after the existing migration chain.

## Structural verification

Before the candidate migrations were applied, the snapshot matched production on:
- 32 tables and 261 columns.
- 153 constraints and 121 indexes.
- 31 RLS policies, with the exact policy definitions compared after correcting the export's command mapping.
- 4 non-internal triggers and 110 application functions.

The staging database now includes the additional idempotency table and functions plus the return-allocation guard. Current staging counts are 33 tables, 267 columns, 154 constraints, 122 indexes, 31 policies, 4 triggers, and 112 functions.

## Acceptance evidence on staging

Synthetic fixtures were run inside transactions that ended with `ROLLBACK`; no fixture rows remain:
- same idempotency key + same payload returns the same sale result;
- same key + changed payload is rejected;
- different key creates a distinct sale;
- stock, inventory movements, audit events, and idempotency records match the expected counts;
- valid partial sale return succeeds when header and line refund allocations match;
- mismatched return refund allocation is rejected before writing a return;
- a complete supplier payment allocation succeeds, while an incomplete allocation is rolled back atomically;
- an authenticated member cannot read another organization's product through RLS;
- client roles cannot TRUNCATE existing public tables in staging, and the `postgres` default-privilege path was tested with a temporary table inside a rolled-back transaction.

## Still unresolved

1. The individual historical SQL sources for the missing migration-history entries have not been recovered. The current snapshot gives us a trustworthy rebuild of the present schema, not proof of each historical migration's provenance.
2. Historical supplier-payment allocation discrepancies and the older sale-return line/header discrepancy remain unchanged in production pending source-document reconciliation.
3. The `supabase_admin` default ACL path in `public` remains a separate platform-permission issue; this work deliberately did not alter it.
4. Full application acceptance still needs coverage for cancellation, customer payments, purchasing and inventory edge cases, reporting, and browser-level flows.

No production migration, financial-data repair, merge, or production deployment was performed.
