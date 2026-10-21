-- Verify the real migration's effects in the disposable CI PostgreSQL database.
DO $test$
DECLARE
  v_table text;
  v_tables text[] := ARRAY['audit_logs', 'customers', 'expenses', 'inventory_movements', 'member_stores', 'organization_members', 'organizations', 'payments', 'permissions', 'products', 'purchase_return_items', 'purchase_returns', 'refunds', 'role_permissions', 'roles', 'sale_items', 'sales', 'stores', 'supplier_refunds', 'customer_payment_allocations', 'customer_payments', 'purchase_receipt_items', 'purchase_receipts', 'sale_return_items', 'sale_returns', 'stock_transfers', 'store_products'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF has_table_privilege('anon', format('public.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'TRUNCATE unexpectedly remains granted to anon on public.%', v_table;
    END IF;
    IF has_table_privilege('authenticated', format('public.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'TRUNCATE unexpectedly remains granted to authenticated on public.%', v_table;
    END IF;
    IF NOT has_table_privilege('service_role', format('public.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'Trusted service_role unexpectedly lost TRUNCATE on public.%', v_table;
    END IF;
  END LOOP;

  IF NOT has_table_privilege('anon', 'public.sales', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.sales', 'SELECT')
     OR NOT has_table_privilege('anon', 'public.sale_items', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.sale_items', 'SELECT') THEN
    RAISE EXCEPTION 'Migration unexpectedly changed SELECT grants';
  END IF;
END
$test$;

CREATE TABLE public.future_privilege_test (id bigint PRIMARY KEY);
DO $default_test$
BEGIN
  IF has_table_privilege('anon', 'public.future_privilege_test', 'TRUNCATE')
     OR has_table_privilege('authenticated', 'public.future_privilege_test', 'TRUNCATE') THEN
    RAISE EXCEPTION 'Postgres default TRUNCATE grant unexpectedly remains for future public tables';
  END IF;
END
$default_test$;

