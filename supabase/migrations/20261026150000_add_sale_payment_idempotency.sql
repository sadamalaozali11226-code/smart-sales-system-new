-- Idempotency protection for sale-payment retries.
-- Existing payment logic remains authoritative; this wrapper stores and replays the first
-- successful response for the same authenticated user, operation, and request key.

create table if not exists private.idempotency_requests (
  user_id uuid not null,
  operation text not null,
  idempotency_key uuid not null,
  request_payload jsonb not null,
  response_payload jsonb,
  created_at timestamptz not null default now(),
  primary key (user_id, operation, idempotency_key)
);

revoke all on table private.idempotency_requests from public, anon, authenticated;

create or replace function private.record_sale_payment_idempotent(
  p_sale_id bigint,
  p_amount numeric,
  p_payment_method text,
  p_reference text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_payload jsonb;
  v_existing_payload jsonb;
  v_response json;
  v_existing_response jsonb;
  v_inserted integer;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if p_idempotency_key is null then
    raise exception 'Idempotency key is required';
  end if;

  v_payload := jsonb_build_object(
    'sale_id', p_sale_id,
    'amount', p_amount,
    'payment_method', coalesce(nullif(trim(p_payment_method), ''), 'cash'),
    'reference', nullif(trim(p_reference), '')
  );

  insert into private.idempotency_requests(
    user_id, operation, idempotency_key, request_payload
  )
  values (v_user_id, 'record_sale_payment', p_idempotency_key, v_payload)
  on conflict (user_id, operation, idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select request_payload, response_payload
      into v_existing_payload, v_existing_response
    from private.idempotency_requests
    where user_id = v_user_id
      and operation = 'record_sale_payment'
      and idempotency_key = p_idempotency_key
    for update;

    if not found then
      raise exception 'Unable to resolve idempotent payment request';
    end if;
    if v_existing_payload <> v_payload then
      raise exception 'Idempotency key was already used for a different payment request';
    end if;
    if v_existing_response is null then
      raise exception 'Payment request is still being processed; retry with the same key';
    end if;

    return v_existing_response;
  end if;

  v_response := private.record_sale_payment(
    p_sale_id, p_amount, p_payment_method, p_reference
  );

  update private.idempotency_requests
  set response_payload = v_response::jsonb
  where user_id = v_user_id
    and operation = 'record_sale_payment'
    and idempotency_key = p_idempotency_key;

  return v_response::jsonb;
end;
$function$;

revoke all on function private.record_sale_payment_idempotent(bigint, numeric, text, text, uuid) from public, anon;
grant execute on function private.record_sale_payment_idempotent(bigint, numeric, text, text, uuid) to authenticated;

create or replace function public.record_sale_payment_idempotent(
  p_sale_id bigint,
  p_amount numeric,
  p_payment_method text,
  p_reference text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
set search_path = 'public', 'private'
as $function$
begin
  return private.record_sale_payment_idempotent(
    p_sale_id, p_amount, p_payment_method, p_reference, p_idempotency_key
  );
end;
$function$;

revoke all on function public.record_sale_payment_idempotent(bigint, numeric, text, text, uuid) from public, anon;
grant execute on function public.record_sale_payment_idempotent(bigint, numeric, text, text, uuid) to authenticated;
