-- Isolated PostgreSQL fixture for the actual public-table privilege migration.
-- CI only. Never run this fixture against Supabase production.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
END
$roles$;

DO $tables$
DECLARE
  v_table text;
  v_tables text[] := ARRAY['audit_logs', 'customers', 'expenses', 'inventory_movements', 'member_stores', 'organization_members', 'organizations', 'payments', 'permissions', 'products', 'purchase_return_items', 'purchase_returns', 'refunds', 'role_permissions', 'roles', 'sale_items', 'sales', 'stores', 'supplier_refunds', 'customer_payment_allocations', 'customer_payments', 'purchase_receipt_items', 'purchase_receipts', 'sale_return_items', 'sale_returns', 'stock_transfers', 'store_products'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    EXECUTE format('CREATE TABLE IF NOT EXISTS public.%I (id bigint PRIMARY KEY)', v_table);
    EXECUTE format('GRANT TRUNCATE ON TABLE public.%I TO anon, authenticated, service_role', v_table);
  END LOOP;
END
$tables$;

GRANT SELECT ON public.sales, public.sale_items TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT TRUNCATE ON TABLES TO anon, authenticated;

DO $baseline_check$
BEGIN
  IF NOT has_table_privilege('anon', 'public.sales', 'TRUNCATE')
     OR NOT has_table_privilege('authenticated', 'public.sales', 'TRUNCATE') THEN
    RAISE EXCEPTION 'Fixture setup failed: expected client TRUNCATE grants on public.sales';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.sales', 'TRUNCATE') THEN
    RAISE EXCEPTION 'Fixture setup failed: service_role should retain TRUNCATE';
  END IF;
END
$baseline_check$;
