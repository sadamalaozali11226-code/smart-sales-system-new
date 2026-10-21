-- Isolated PostgreSQL fixture only. Never run against Supabase production.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin NOLOGIN;
  END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS audit_default_truncate_test;
GRANT USAGE, CREATE ON SCHEMA audit_default_truncate_test TO supabase_admin;

-- Model the risky default ACL shape observed in the production catalog.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA audit_default_truncate_test
  GRANT TRUNCATE ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA audit_default_truncate_test
  GRANT TRUNCATE ON TABLES TO anon, authenticated;

CREATE TABLE audit_default_truncate_test.existing_postgres (id bigint PRIMARY KEY);
GRANT SELECT ON audit_default_truncate_test.existing_postgres TO authenticated;

SET ROLE supabase_admin;
CREATE TABLE audit_default_truncate_test.existing_supabase_admin (id bigint PRIMARY KEY);
RESET ROLE;

DO $baseline_check$
BEGIN
  IF NOT has_table_privilege('anon', 'audit_default_truncate_test.existing_postgres', 'TRUNCATE')
     OR NOT has_table_privilege('authenticated', 'audit_default_truncate_test.existing_postgres', 'TRUNCATE') THEN
    RAISE EXCEPTION 'Fixture setup failed: postgres-created table lacks expected default TRUNCATE grants';
  END IF;
  IF NOT has_table_privilege('anon', 'audit_default_truncate_test.existing_supabase_admin', 'TRUNCATE')
     OR NOT has_table_privilege('authenticated', 'audit_default_truncate_test.existing_supabase_admin', 'TRUNCATE') THEN
    RAISE EXCEPTION 'Fixture setup failed: supabase_admin-created table lacks expected default TRUNCATE grants';
  END IF;
  IF NOT has_table_privilege('authenticated', 'audit_default_truncate_test.existing_postgres', 'SELECT') THEN
    RAISE EXCEPTION 'Fixture setup failed: expected SELECT grant is missing';
  END IF;
END
$baseline_check$;
