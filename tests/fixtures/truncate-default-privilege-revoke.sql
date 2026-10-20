-- Candidate remediation logic tested only in the isolated PostgreSQL fixture.
REVOKE TRUNCATE ON TABLE
  audit_default_truncate_test.existing_postgres,
  audit_default_truncate_test.existing_supabase_admin
FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA audit_default_truncate_test
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA audit_default_truncate_test
  REVOKE TRUNCATE ON TABLES FROM anon, authenticated;

-- Simulate future tables created by each role after default-ACL remediation.
CREATE TABLE audit_default_truncate_test.future_postgres (id bigint PRIMARY KEY);
SET ROLE supabase_admin;
CREATE TABLE audit_default_truncate_test.future_supabase_admin (id bigint PRIMARY KEY);
RESET ROLE;
