# Proposed PostgreSQL privilege hardening — review only

**Status:** proposal, not a migration.  
**Branch:** `audit/priority-integrity-2026-10-18`  
**Production changes:** none. Do not execute this document against production without a separately approved change window.

## Confirmed read-only observations (2026-10-18)

- In `public`, 27 existing tables had an explicit ACL entry granting `TRUNCATE` to `authenticated`.
- Of those, 19 also had `TRUNCATE` granted to `anon`.
- The 27-table set is: `audit_logs`, `customers`, `expenses`, `inventory_movements`, `member_stores`, `organization_members`, `organizations`, `payments`, `permissions`, `products`, `purchase_return_items`, `purchase_returns`, `refunds`, `role_permissions`, `roles`, `sale_items`, `sales`, `stores`, `supplier_refunds`, `customer_payment_allocations`, `customer_payments`, `purchase_receipt_items`, `purchase_receipts`, `sale_return_items`, `sale_returns`, `stock_transfers`, `store_products`.
- Read-only inspection of `pg_default_acl` found default `TRUNCATE` grants for `anon` and `authenticated` on tables created in `public` by both `postgres` and `supabase_admin`.
- No database DDL, GRANT, REVOKE, data modification, or migration was run during this investigation.

These findings identify a concrete current privilege problem and a likely ongoing source for at least some grants. Default ACLs do not record when each existing table's grant was made, so they do not prove the historical source of every current table ACL.

## Candidate SQL — existing application tables

This explicit list is limited to the 27 `public` tables returned by the read-only ACL query. It does not change `SELECT`, `INSERT`, `UPDATE`, `DELETE`, sequence, function, storage, or RLS permissions.

```sql
REVOKE TRUNCATE ON TABLE
  public.audit_logs,
  public.customers,
  public.expenses,
  public.inventory_movements,
  public.member_stores,
  public.organization_members,
  public.organizations,
  public.payments,
  public.permissions,
  public.products,
  public.purchase_return_items,
  public.purchase_returns,
  public.refunds,
  public.role_permissions,
  public.roles,
  public.sale_items,
  public.sales,
  public.stores,
  public.supplier_refunds,
  public.customer_payment_allocations,
  public.customer_payments,
  public.purchase_receipt_items,
  public.purchase_receipts,
  public.sale_return_items,
  public.sale_returns,
  public.stock_transfers,
  public.store_products
FROM anon, authenticated;
```

## Candidate SQL — future tables in `public`

Read-only catalog results show default ACL entries associated with both `postgres` and `supabase_admin`. This candidate addresses only the `TRUNCATE` default privilege for those creator roles in `public`; it does not alter defaults for `storage`, `graphql`, or `graphql_public`.

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;
```

**Pre-application gate:** verify that the migration execution role is authorized to change default privileges for both creator roles, and confirm that Supabase-managed role `supabase_admin` defaults are intended to be changed by an application migration. If that cannot be established, do not include the second statement in a production migration; escalate it for an approved platform-specific remediation. The second statement is a candidate for review, not an instruction to run now.

## Verification queries (read-only; run after an approved change)

### Existing `public` tables

```sql
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS owner_name,
       has_table_privilege('anon', c.oid, 'TRUNCATE') AS anon_can_truncate,
       has_table_privilege('authenticated', c.oid, 'TRUNCATE') AS authenticated_can_truncate
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND (
    has_table_privilege('anon', c.oid, 'TRUNCATE')
    OR has_table_privilege('authenticated', c.oid, 'TRUNCATE')
  )
ORDER BY c.relname;
```

Expected result for the current application table set: no rows. If other `public` tables appear, classify each one before expanding the scope; do not automatically revoke unrelated platform privileges.

### Default ACLs for future `public` tables

```sql
SELECT pg_get_userbyid(d.defaclrole) AS creator_role,
       n.nspname AS schema_name,
       gr.rolname AS grantee,
       x.privilege_type
FROM pg_default_acl d
JOIN pg_namespace n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) x
JOIN pg_roles gr ON gr.oid = x.grantee
WHERE n.nspname = 'public'
  AND d.defaclobjtype = 'r'
  AND gr.rolname IN ('anon', 'authenticated')
  AND x.privilege_type = 'TRUNCATE'
ORDER BY creator_role, grantee;
```

Expected result: no rows for the reviewed `postgres` and `supabase_admin` creator roles. Also re-check for global default ACL entries before relying on schema-scoped results.

## Separate `anon SELECT` finding — RLS context

A read-only catalog check found that `anon` has the SQL `SELECT` privilege on both `public.sales` and `public.sale_items`. RLS is enabled on both tables, and the listed SELECT policies target only the `authenticated` role (`sales_select_store_member` and `sale_items_select_sale_member`). This is a narrower exposure than an unfiltered public read, but it remains an unnecessary direct grant worth reviewing. Catalog inspection alone is not a runtime proof of what the `anon` role can read; validate with an isolated role-level query test before deciding whether to revoke `SELECT`. This proposal intentionally leaves that privilege unchanged.

## Required isolated test and release gates

1. Test the candidate SQL in a disposable PostgreSQL instance whose ACLs model the observed grants, including defaults for both creator roles where practical.
2. Verify `anon` and `authenticated` lose `TRUNCATE` while required `SELECT` permissions and trusted server-side write paths remain intact.
3. Run the application's integration/acceptance tests for sales, returns, cancellations, customer payments, purchase receipts, and supplier payments against an isolated database. Existing CI fixture coverage alone is not sufficient.
4. Review the separate finding that `anon` has `SELECT` on `public.sales` and `public.sale_items`; this proposal intentionally does not change it.
5. Only after review, create a proper migration using the repository's approved Supabase migration workflow. Do not execute SQL from this document directly on production.
6. Do not merge PR #49 or deploy any change until the user explicitly approves.

## Scope and limitations

- This is a review document, not a migration file under `supabase/migrations/`.
- It does not prove that the application has a user-accessible operation capable of invoking `TRUNCATE`, nor that data loss occurred.
- It does not cover role membership, other schemas, or the separate `anon SELECT` concern.
- No production permissions were changed while preparing this proposal.
