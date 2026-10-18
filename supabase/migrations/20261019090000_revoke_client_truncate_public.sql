-- Narrow privilege hardening for application tables in public.
-- This migration is intentionally limited to TRUNCATE. It does not change RLS,
-- row-level CRUD grants, sequences, functions, or service_role privileges.
--
-- Prepared on the isolated audit branch only. Do not apply to production until
-- the migration execution role and release window have been reviewed/approved.

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

-- Prevent the same grants from being inherited by future public tables created
-- by the normal application migration role.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;

-- Follow-up required before production release:
-- Production catalog inspection also found default TRUNCATE ACL entries for
-- supabase_admin in public. The current postgres role membership does not show
-- membership in supabase_admin, so this migration deliberately does not attempt
-- ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin. Handle that platform-managed
-- default ACL only after confirming the supported administrative path. Do not
-- broaden this migration to storage/graphql/graphql_public defaults.
