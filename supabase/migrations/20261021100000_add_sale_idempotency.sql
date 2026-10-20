-- Durable sale idempotency for retries after a committed RPC response is lost.
-- This is a migration candidate; it must be applied to an isolated database before production approval.

-- Fail early if the production sale implementation has drifted from the
-- exact function contract this wrapper delegates to. Never guess at a replacement.
do $preflight$
declare
  v_security_definer boolean;
  v_config text[];
begin
  if to_regprocedure('private.create_sale_transaction(uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)') is null then
    raise exception 'Cannot install sale idempotency: expected private.create_sale_transaction signature is missing';
  end if;

  select prosecdef, proconfig
    into v_security_definer, v_config
    from pg_proc
   where oid = 'private.create_sale_transaction(uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)'::regprocedure;

  if not coalesce(v_security_definer, false) then
    raise exception 'Cannot install sale idempotency: underlying sale function must remain SECURITY DEFINER';
  end if;

  if not coalesce(v_config @> array['search_path=""'], false) then
    raise exception 'Cannot install sale idempotency: underlying sale function must pin an empty search_path';
  end if;
end;
$preflight$;

create table if not exists private.sale_idempotency_requests (
  organization_id uuid not null,
  store_id uuid not null,
  idempotency_key uuid not null,
  payload_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (organization_id, store_id, idempotency_key)
);

revoke all on table private.sale_idempotency_requests from public, anon, authenticated;

create or replace function private.create_sale_transaction_idempotent(
  p_idempotency_key uuid,
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
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payload_hash text;
  v_existing_hash text;
  v_response jsonb;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if p_idempotency_key is null then
    raise exception 'idempotency key is required';
  end if;
  if p_organization_id is null or p_store_id is null then
    raise exception 'organization and store are required';
  end if;
  if not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'not authorized for this store';
  end if;
  if not private.has_org_permission(p_organization_id, 'sales.create') then
    raise exception 'sales.create permission required';
  end if;

  v_payload_hash := md5(jsonb_build_object(
    'organization_id', p_organization_id,
    'store_id', p_store_id,
    'invoice_number', p_invoice_number,
    'customer_id', p_customer_id,
    'items', p_items,
    'discount', p_discount,
    'tax', p_tax,
    'paid_amount', p_paid_amount,
    'payment_method', p_payment_method,
    'reference', p_reference,
    'notes', p_notes
  )::text);

  -- Serialize retries for this key. Hash collisions only serialize unrelated requests;
  -- the table's primary key remains the authoritative uniqueness constraint.
  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_store_id::text || ':' || p_idempotency_key::text,
    0
  ));

  select payload_hash, response
    into v_existing_hash, v_response
    from private.sale_idempotency_requests
   where organization_id = p_organization_id
     and store_id = p_store_id
     and idempotency_key = p_idempotency_key;

  if found then
    if v_existing_hash <> v_payload_hash then
      raise exception 'idempotency key was already used for a different sale payload';
    end if;
    return v_response;
  end if;

  v_response := private.create_sale_transaction(
    p_organization_id,
    p_store_id,
    p_invoice_number,
    p_customer_id,
    p_items,
    p_discount,
    p_tax,
    p_paid_amount,
    p_payment_method,
    p_reference,
    p_notes
  );

  insert into private.sale_idempotency_requests (
    organization_id, store_id, idempotency_key, payload_hash, response
  ) values (
    p_organization_id, p_store_id, p_idempotency_key, v_payload_hash, v_response
  );

  return v_response;
end;
$function$;

revoke all on function private.create_sale_transaction_idempotent(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.create_sale_transaction_idempotent(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text) to authenticated;

create or replace function public.create_sale_transaction(
  p_idempotency_key uuid,
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
  select private.create_sale_transaction_idempotent(
    p_idempotency_key,
    p_organization_id,
    p_store_id,
    p_invoice_number,
    p_customer_id,
    p_items,
    p_discount,
    p_tax,
    p_paid_amount,
    p_payment_method,
    p_reference,
    p_notes
  );
$function$;

revoke all on function public.create_sale_transaction(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text) from public, anon;
grant execute on function public.create_sale_transaction(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text) to authenticated;

-- Remove the legacy public overload so PostgREST cannot resolve a retry to the
-- non-idempotent entry point when clients omit p_idempotency_key.
drop function if exists public.create_sale_transaction(uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text);

notify pgrst, 'reload schema';
