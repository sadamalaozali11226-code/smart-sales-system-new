\set ON_ERROR_STOP on
do $test$
declare
  v_first jsonb;
  v_retry jsonb;
  v_second jsonb;
  v_calls integer;
  v_public_security_definer boolean;
  v_helper_security_definer boolean;
  v_helper_search_path text;
  v_key uuid := '10000000-0000-0000-0000-000000000001';
  v_other_key uuid := '10000000-0000-0000-0000-000000000002';
  v_org uuid := '20000000-0000-0000-0000-000000000001';
  v_store uuid := '30000000-0000-0000-0000-000000000001';
  v_items jsonb := '[{"product_id":1,"quantity":2,"discount":0}]'::jsonb;
begin
  -- Supply a deterministic authenticated subject to Supabase's built-in auth.uid().
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);

  if to_regprocedure('public.create_sale_transaction(uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)') is not null then
    raise exception 'legacy non-idempotent public RPC overload must be removed';
  end if;

  select prosecdef into v_public_security_definer
    from pg_proc
   where oid = 'public.create_sale_transaction(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)'::regprocedure;
  if v_public_security_definer then raise exception 'public RPC wrapper must not be SECURITY DEFINER'; end if;

  select prosecdef, array_to_string(proconfig, ',')
    into v_helper_security_definer, v_helper_search_path
    from pg_proc
   where oid = 'private.create_sale_transaction_idempotent(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)'::regprocedure;
  if not v_helper_security_definer then raise exception 'internal idempotency helper must be SECURITY DEFINER'; end if;
  if position('search_path=""' in coalesce(v_helper_search_path, '')) = 0 then
    raise exception 'internal helper must pin an empty search_path; got %', v_helper_search_path;
  end if;

  if not has_function_privilege('authenticated', 'public.create_sale_transaction(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)', 'EXECUTE') then
    raise exception 'authenticated role must be able to execute the public RPC';
  end if;
  if has_function_privilege('anon', 'public.create_sale_transaction(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)', 'EXECUTE') then
    raise exception 'anon role must not be able to execute the public RPC';
  end if;
  if not has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'authenticated role must have schema USAGE for the invoker RPC';
  end if;
  if not has_function_privilege('authenticated', 'private.create_sale_transaction_idempotent(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)', 'EXECUTE') then
    raise exception 'authenticated role must be able to execute the internal helper';
  end if;
  if has_function_privilege('anon', 'private.create_sale_transaction_idempotent(uuid,uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)', 'EXECUTE') then
    raise exception 'anon role must not be able to execute the internal helper';
  end if;
  if has_table_privilege('authenticated', 'private.sale_idempotency_requests', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'authenticated role must not have direct access to the idempotency table';
  end if;
  if has_table_privilege('anon', 'private.sale_idempotency_requests', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'anon role must not have direct access to the idempotency table';
  end if;

  v_first := public.create_sale_transaction(
    v_key, v_org, v_store, null, null, v_items, 0, 0, 0, 'cash', null, null
  );
  v_retry := public.create_sale_transaction(
    v_key, v_org, v_store, null, null, v_items, 0, 0, 0, 'cash', null, null
  );
  if v_first <> v_retry then raise exception 'retry did not return the original sale response'; end if;

  select call_count into v_calls from private.sale_calls;
  if v_calls <> 1 then raise exception 'expected one underlying sale call after retry, got %', v_calls; end if;

  begin
    perform public.create_sale_transaction(
      v_key, v_org, v_store, null, null,
      '[{"product_id":1,"quantity":3,"discount":0}]'::jsonb,
      0, 0, 0, 'cash', null, null
    );
    raise exception 'same key with changed payload unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'same key with changed payload unexpectedly succeeded' then raise; end if;
    if position('different sale payload' in sqlerrm) = 0 then raise; end if;
  end;

  v_second := public.create_sale_transaction(
    v_other_key, v_org, v_store, null, null, v_items, 0, 0, 0, 'cash', null, null
  );
  if v_second->>'sale_id' <> '2' then raise exception 'new key did not create a new sale'; end if;

  select call_count into v_calls from private.sale_calls;
  if v_calls <> 2 then raise exception 'expected two underlying sale calls for two keys, got %', v_calls; end if;
end;
$test$;
