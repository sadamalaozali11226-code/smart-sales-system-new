DO $test$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'existing_postgres',
    'existing_supabase_admin',
    'future_postgres',
    'future_supabase_admin'
  ];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    IF has_table_privilege('anon', format('audit_default_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'TRUNCATE unexpectedly remains granted to anon on audit_default_truncate_test.%', v_table;
    END IF;
    IF has_table_privilege('authenticated', format('audit_default_truncate_test.%I', v_table), 'TRUNCATE') THEN
      RAISE EXCEPTION 'TRUNCATE unexpectedly remains granted to authenticated on audit_default_truncate_test.%', v_table;
    END IF;
  END LOOP;

  IF NOT has_table_privilege('authenticated', 'audit_default_truncate_test.existing_postgres', 'SELECT') THEN
    RAISE EXCEPTION 'Narrow revocation unexpectedly removed SELECT from existing_postgres';
  END IF;

  RAISE NOTICE 'isolated existing/default TRUNCATE revocation assertions passed';
END
$test$;
