-- Isolated PostgreSQL fixture only. Models the observed production ACL shape;
-- it does not connect to Supabase or prove who granted production privileges.
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

CREATE SCHEMA IF NOT EXISTS audit_truncate_test;

DO $tables$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'audit_logs', 'customers', 'expenses', 'inventory_movements',
    'member_stores', 'organization_invitations', 'organization_members', 'organizations', 'payments',
    'permissions', 'products', 'purchase_return_items', 'purchase_returns',
    'refunds', 'role_permissions', 'roles', 'sale_items', 'sales', 'stores',
    'supplier_refunds', 'supplier_payment_allocations', 'supplier_payments', 'suppliers', 'customer_payment_allocations', 'customer_payments',
    'purchase_receipt_items', 'purchase_receipts', 'sale_return_items',
    'sale_returns', 'stock_transfers', 'store_products'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    EXECUTE format('CREATE TABLE audit_truncate_test.%I (id bigint PRIMARY KEY)', v_table);
    EXECUTE format('GRANT TRUNCATE ON TABLE audit_truncate_test.%I TO authenticated, service_role', v_table);
  END LOOP;
END
$tables$;

-- Production read-only inspection found anon TRUNCATE on these 19 of 31 tables.
GRANT TRUNCATE ON TABLE
  audit_truncate_test.audit_logs,
  audit_truncate_test.customers,
  audit_truncate_test.expenses,
  audit_truncate_test.inventory_movements,
  audit_truncate_test.member_stores,
  audit_truncate_test.organization_members,
  audit_truncate_test.organizations,
  audit_truncate_test.payments,
  audit_truncate_test.permissions,
  audit_truncate_test.products,
  audit_truncate_test.purchase_return_items,
  audit_truncate_test.purchase_returns,
  audit_truncate_test.refunds,
  audit_truncate_test.role_permissions,
  audit_truncate_test.roles,
  audit_truncate_test.sale_items,
  audit_truncate_test.sales,
  audit_truncate_test.stores,
  audit_truncate_test.supplier_refunds
TO anon;

-- These SELECT grants model a separate observed privilege and must survive
-- the narrowly scoped TRUNCATE remediation.
GRANT SELECT ON TABLE audit_truncate_test.sales, audit_truncate_test.sale_items TO anon;
GRANT SELECT ON TABLE audit_truncate_test.sales TO authenticated;

DO $baseline_check$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'audit_logs', 'customers', 'expenses', 'inventory_movements',
    'member_stores', 'organization_members', 'organizations', 'payments',
    'permissions', 'products', 'purchase_return_items', 'purchase_returns',
    'refunds', 'role_permissions', 'roles', 'sale_items', 'sales', 'stores',
    'supplier_refunds', 'customer_payment_allocations', 'customer_payments',
    'purchase_receipt_items', 'purchase_receipts', 'sale_return_items',
    'sale_returns', 'stock_transfers', 'store_products'
  ];
  v_anon_tables text[] := ARRAY[
    'audit_logs', 'customers', 'expenses', 'inventory_movements',
    'member_stores', 'organization_members', 'organizations', 'payments',
    'permissions', 'products', 'purchase_return_items', 'purchase_returns',
    'refunds', 'role_permissions', 'roles', 'sale_items', 'sales', 'stores',
    'supplier_refunds'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF NOT has_table_privilege('authenticated', format('audit_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'Fixture setup failed: authenticated lacks expected TRUNCATE on %', v_table;
    END IF;
  END LOOP;
  FOREACH v_table IN ARRAY v_anon_tables LOOP
    IF NOT has_table_privilege('anon', format('audit_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'Fixture setup failed: anon lacks expected TRUNCATE on %', v_table;
    END IF;
  END LOOP;
  IF NOT has_table_privilege('anon', 'audit_truncate_test.sales', 'SELECT')
     OR NOT has_table_privilege('anon', 'audit_truncate_test.sale_items', 'SELECT') THEN
    RAISE EXCEPTION 'Fixture setup failed: expected anon SELECT grants are missing';
  END IF;
  IF NOT has_table_privilege('authenticated', 'audit_truncate_test.sales', 'SELECT') THEN
    RAISE EXCEPTION 'Fixture setup failed: expected authenticated SELECT grant is missing';
  END IF;
END
$baseline_check$;
