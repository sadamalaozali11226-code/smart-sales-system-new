-- Isolated PostgreSQL fixture only. This models the observed privilege shape;
-- it does not connect to Supabase or prove who granted production privileges.
do $role$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$role$;

create schema if not exists audit_truncate_test;

create table audit_truncate_test.sales (id bigint primary key);
create table audit_truncate_test.sale_items (id bigint primary key);
create table audit_truncate_test.sale_returns (id bigint primary key);
create table audit_truncate_test.sale_return_items (id bigint primary key);
create table audit_truncate_test.customer_payments (id bigint primary key);
create table audit_truncate_test.customer_payment_allocations (id bigint primary key);
create table audit_truncate_test.purchase_receipts (id bigint primary key);
create table audit_truncate_test.purchase_receipt_items (id bigint primary key);

grant truncate on table
  audit_truncate_test.sales,
  audit_truncate_test.sale_items,
  audit_truncate_test.sale_returns,
  audit_truncate_test.sale_return_items,
  audit_truncate_test.customer_payments,
  audit_truncate_test.customer_payment_allocations,
  audit_truncate_test.purchase_receipts,
  audit_truncate_test.purchase_receipt_items
to authenticated;

-- A separate privilege is included to ensure the candidate revocation is narrow.
grant select on table audit_truncate_test.sales to authenticated;
