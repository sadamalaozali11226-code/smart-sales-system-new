DO $test$
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
    IF has_table_privilege('anon', format('audit_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'TRUNCATE unexpectedly remains granted to anon on %', v_table;
    END IF;
    IF has_table_privilege('authenticated', format('audit_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'TRUNCATE unexpectedly remains granted to authenticated on %', v_table;
    END IF;
    IF NOT has_table_privilege('service_role', format('audit_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'Trusted service_role unexpectedly lost TRUNCATE on %', v_table;
    END IF;
  END LOOP;

  IF NOT has_table_privilege('anon', 'audit_truncate_test.sales', 'SELECT')
     OR NOT has_table_privilege('anon', 'audit_truncate_test.sale_items', 'SELECT') THEN
    RAISE EXCEPTION 'Narrow TRUNCATE revocation unexpectedly removed anon SELECT';
  END IF;
  IF NOT has_table_privilege('authenticated', 'audit_truncate_test.sales', 'SELECT') THEN
    RAISE EXCEPTION 'Narrow TRUNCATE revocation unexpectedly removed authenticated SELECT';
  END IF;

  RAISE NOTICE 'isolated 31-table anon/authenticated TRUNCATE revocation assertions passed';
END
$test$;
