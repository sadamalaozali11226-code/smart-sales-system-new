\set ON_ERROR_STOP on
create schema if not exists auth;
create schema if not exists private;

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end;
$roles$;

create or replace function auth.uid()
returns uuid language sql stable
as $function$ select '00000000-0000-0000-0000-000000000001'::uuid $function$;

create or replace function private.is_org_store_member(uuid, uuid)
returns boolean language sql stable
as $function$ select true $function$;

create or replace function private.has_org_permission(uuid, text)
returns boolean language sql stable
as $function$ select true $function$;

create table private.sale_calls(call_count integer not null);
insert into private.sale_calls values (0);

create or replace function private.create_sale_transaction(
  p_organization_id uuid,
  p_store_id uuid,
  p_invoice_number text,
  p_customer_id bigint,
  p_items jsonb,
  p_discount numeric,
  p_tax numeric,
  p_paid_amount numeric,
  p_payment_method text,
  p_reference text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  update private.sale_calls set call_count = call_count + 1 returning call_count into v_count;
  return jsonb_build_object('sale_id', v_count, 'invoice_number', 'INV-' || v_count::text);
end;
$function$;
