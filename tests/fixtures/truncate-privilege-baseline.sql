-- Isolated PostgreSQL fixture only. This models the observed privilege shape;
-- it does not connect to Supabase or prove who granted production privileges.
do $role$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$role$;

create table public.sales (id bigint primary key);
create table public.sale_items (id bigint primary key);
create table public.sale_returns (id bigint primary key);
create table public.sale_return_items (id bigint primary key);
create table public.customer_payments (id bigint primary key);
create table public.customer_payment_allocations (id bigint primary key);
create table public.purchase_receipts (id bigint primary key);
create table public.purchase_receipt_items (id bigint primary key);

grant truncate on table
  public.sales,
  public.sale_items,
  public.sale_returns,
  public.sale_return_items,
  public.customer_payments,
  public.customer_payment_allocations,
  public.purchase_receipts,
  public.purchase_receipt_items
to authenticated;

-- A separate privilege is included to ensure the candidate revocation is narrow.
grant select on table public.sales to authenticated;
