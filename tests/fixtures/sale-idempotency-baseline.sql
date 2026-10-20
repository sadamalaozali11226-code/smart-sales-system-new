\set ON_ERROR_STOP on
create schema if not exists auth;
create schema if not exists private;

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end;
$roles$;

-- Plain PostgreSQL CI has no Supabase auth.uid(); local Supabase already has it,
-- owned by its auth administrator, so never replace the built-in function there.
do $auth_uid$
begin
  if to_regprocedure('auth.uid()') is null then
    execute $create_fn$
      create function auth.uid()
      returns uuid language sql stable
      as $fn$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $fn$
    $create_fn$;
  end if;
end;
$auth_uid$;

-- Controllable authorization doubles let tests verify that the helper rejects
-- callers without store membership or the sales.create permission.
create or replace function private.is_org_store_member(uuid, uuid)
returns boolean language sql stable
as $function$
  select coalesce(nullif(current_setting('test.is_org_store_member', true), '')::boolean, true)
$function$;

create or replace function private.has_org_permission(uuid, text)
returns boolean language sql stable
as $function$
  select coalesce(nullif(current_setting('test.has_org_permission', true), '')::boolean, true)
$function$;

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
  -- Make simultaneous requests overlap so the concurrency regression test is meaningful.
  perform pg_sleep(0.3);
  update private.sale_calls set call_count = call_count + 1 returning call_count into v_count;
  return jsonb_build_object('sale_id', v_count, 'invoice_number', 'INV-' || v_count::text);
end;
$function$;


-- Model the legacy public RPC overload present before the idempotency migration.
create or replace function public.create_sale_transaction(
  p_organization_id uuid,
  p_store_id uuid,
  p_invoice_number text,
  p_customer_id bigint default null,
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0,
  p_tax numeric default 0,
  p_paid_amount numeric default 0,
  p_payment_method text default 'cash',
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.create_sale_transaction(
    p_organization_id, p_store_id, p_invoice_number, p_customer_id,
    p_items, p_discount, p_tax, p_paid_amount, p_payment_method, p_reference, p_notes
  );
$function$;
