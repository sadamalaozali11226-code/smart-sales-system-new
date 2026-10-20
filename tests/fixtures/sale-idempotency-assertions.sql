\set ON_ERROR_STOP on
do $test$
declare
  v_first jsonb;
  v_retry jsonb;
  v_second jsonb;
  v_calls integer;
  v_key uuid := '10000000-0000-0000-0000-000000000001';
  v_other_key uuid := '10000000-0000-0000-0000-000000000002';
  v_org uuid := '20000000-0000-0000-0000-000000000001';
  v_store uuid := '30000000-0000-0000-0000-000000000001';
  v_items jsonb := '[{"product_id":1,"quantity":2,"discount":0}]'::jsonb;
begin
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
