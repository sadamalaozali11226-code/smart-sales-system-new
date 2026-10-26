-- Expose the existing sale-creation idempotency helper through an authenticated RPC.
-- The helper serializes retries for a key and replays the original sale response.

create table if not exists private.sale_idempotency_requests (
  organization_id uuid not null,
  store_id uuid not null,
  idempotency_key uuid not null,
  payload jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (organization_id, store_id, idempotency_key)
);

alter table private.sale_idempotency_requests enable row level security;
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
  v_payload jsonb;
  v_existing_payload jsonb;
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

  v_payload := jsonb_build_object(
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
  );

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_store_id::text || ':' || p_idempotency_key::text,
    0
  ));

  select payload, response
    into v_existing_payload, v_response
    from private.sale_idempotency_requests
   where organization_id = p_organization_id
     and store_id = p_store_id
     and idempotency_key = p_idempotency_key;

  if found then
    if v_existing_payload <> v_payload then
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
    organization_id, store_id, idempotency_key, payload, response
  ) values (
    p_organization_id, p_store_id, p_idempotency_key, v_payload, v_response
  );

  return v_response;
end;
$function$;

revoke all on function private.create_sale_transaction_idempotent(uuid, uuid, uuid, text, bigint, jsonb, numeric, numeric, numeric, text, text, text) from public, anon;
grant execute on function private.create_sale_transaction_idempotent(uuid, uuid, uuid, text, bigint, jsonb, numeric, numeric, numeric, text, text, text) to authenticated;

create or replace function public.create_sale_transaction_idempotent(
  p_idempotency_key uuid,
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
set search_path = 'public', 'private'
as $function$
begin
  return private.create_sale_transaction_idempotent(
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
end;
$function$;

revoke all on function public.create_sale_transaction_idempotent(uuid, uuid, uuid, text, bigint, jsonb, numeric, numeric, numeric, text, text, text) from public, anon;
grant execute on function public.create_sale_transaction_idempotent(uuid, uuid, uuid, text, bigint, jsonb, numeric, numeric, numeric, text, text, text) to authenticated;
