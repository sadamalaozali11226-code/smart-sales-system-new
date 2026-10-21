\set ON_ERROR_STOP on

do $test$
declare
  v_org uuid := '20000000-0000-0000-0000-000000000001';
  v_store uuid := '30000000-0000-0000-0000-000000000001';
  v_user uuid := '00000000-0000-0000-0000-000000000001';
  v_key uuid := '10000000-0000-0000-0000-000000000001';
  v_other_key uuid := '10000000-0000-0000-0000-000000000002';
  v_failed_key uuid := '10000000-0000-0000-0000-000000000003';
  v_product_id bigint;
  v_first jsonb;
  v_retry jsonb;
  v_second jsonb;
  v_stock integer;
begin
  perform set_config('request.jwt.claim.sub', v_user::text, false);

  insert into public.products (organization_id, name, price)
  values (v_org, 'Integration Test Product', 10)
  returning id into v_product_id;

  insert into public.store_products (store_id, product_id, quantity, average_cost, cost_known)
  values (v_store, v_product_id, 10, 2.5, true);

  v_first := public.create_sale_transaction(
    v_key, v_org, v_store, null, null,
    jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 2, 'discount', 0)),
    0, 0, 5, 'cash', 'PAY-TEST-1', 'idempotency integration test'
  );
  v_retry := public.create_sale_transaction(
    v_key, v_org, v_store, null, null,
    jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 2, 'discount', 0)),
    0, 0, 5, 'cash', 'PAY-TEST-1', 'idempotency integration test'
  );

  if v_first <> v_retry then raise exception 'identical retry did not return the original response'; end if;
  if v_first->>'invoice_number' <> 'INV-000001' then
    raise exception 'unexpected first invoice number: %', v_first->>'invoice_number';
  end if;
  if v_first->>'total' <> '20' or v_first->>'payment_status' <> 'partial' then
    raise exception 'first sale totals/payment status incorrect: %', v_first;
  end if;

  if (select count(*) from public.sales) <> 1 then raise exception 'identical retry created duplicate sales'; end if;
  if (select count(*) from public.sale_items) <> 1 then raise exception 'identical retry duplicated sale items'; end if;
  if (select count(*) from public.inventory_movements) <> 1 then raise exception 'identical retry duplicated stock movements'; end if;
  if (select count(*) from public.payments) <> 1 then raise exception 'identical retry duplicated payments'; end if;
  if (select count(*) from public.audit_logs where action = 'sale.created') <> 1 then
    raise exception 'identical retry duplicated audit entries';
  end if;
  select quantity into v_stock from public.store_products where store_id = v_store and product_id = v_product_id;
  if v_stock <> 8 then raise exception 'stock after first sale should be 8, got %', v_stock; end if;

  begin
    perform public.create_sale_transaction(
      v_key, v_org, v_store, null, null,
      jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 3, 'discount', 0)),
      0, 0, 5, 'cash', 'PAY-TEST-1', 'idempotency integration test'
    );
    raise exception 'same idempotency key with changed payload unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'same idempotency key with changed payload unexpectedly succeeded' then raise; end if;
    if position('different sale payload' in sqlerrm) = 0 then raise; end if;
  end;

  v_second := public.create_sale_transaction(
    v_other_key, v_org, v_store, null, null,
    jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 1, 'discount', 0)),
    0, 0, 10, 'cash', 'PAY-TEST-2', 'second distinct sale'
  );
  if v_second->>'invoice_number' <> 'INV-000002' then
    raise exception 'unexpected second invoice number: %', v_second->>'invoice_number';
  end if;
  if v_second->>'total' <> '10' or v_second->>'payment_status' <> 'paid' then
    raise exception 'second sale totals/payment status incorrect: %', v_second;
  end if;

  if (select count(*) from public.sales) <> 2 then raise exception 'expected exactly two distinct sales'; end if;
  if (select count(*) from public.sale_items) <> 2 then raise exception 'expected exactly two sale item rows'; end if;
  if (select count(*) from public.inventory_movements) <> 2 then raise exception 'expected exactly two stock movements'; end if;
  if (select count(*) from public.payments) <> 2 then raise exception 'expected one payment per paid/partial sale'; end if;
  if (select count(*) from public.audit_logs where action = 'sale.created') <> 2 then
    raise exception 'expected exactly two sale audit entries';
  end if;
  select quantity into v_stock from public.store_products where store_id = v_store and product_id = v_product_id;
  if v_stock <> 7 then raise exception 'stock after two distinct sales should be 7, got %', v_stock; end if;

  begin
    perform public.create_sale_transaction(
      v_failed_key, v_org, v_store, null, null,
      jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 100, 'discount', 0)),
      0, 0, 0, 'cash', null, 'insufficient stock test'
    );
    raise exception 'sale with insufficient stock unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'sale with insufficient stock unexpectedly succeeded' then raise; end if;
    if position('insufficient stock' in sqlerrm) = 0 then raise; end if;
  end;

  if (select count(*) from public.sales) <> 2 then raise exception 'failed sale left a sales row behind'; end if;
  if (select count(*) from private.sale_idempotency_requests) <> 2 then
    raise exception 'failed sale left an idempotency record behind';
  end if;
  select quantity into v_stock from public.store_products where store_id = v_store and product_id = v_product_id;
  if v_stock <> 7 then raise exception 'failed sale changed stock; expected 7, got %', v_stock; end if;

  perform set_config('test.has_org_permission', 'false', false);
  begin
    perform public.create_sale_transaction(
      v_failed_key, v_org, v_store, null, null,
      jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 1, 'discount', 0)),
      0, 0, 0, 'cash', null, 'permission test'
    );
    raise exception 'sale without sales.create permission unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'sale without sales.create permission unexpectedly succeeded' then raise; end if;
    if position('sales.create permission required' in sqlerrm) = 0 then raise; end if;
  end;
  perform set_config('test.has_org_permission', 'true', false);

  perform set_config('request.jwt.claim.sub', '', false);
  begin
    perform public.create_sale_transaction(
      v_failed_key, v_org, v_store, null, null,
      jsonb_build_array(jsonb_build_object('product_id', v_product_id, 'quantity', 1, 'discount', 0)),
      0, 0, 0, 'cash', null, 'authentication test'
    );
    raise exception 'unauthenticated sale unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'unauthenticated sale unexpectedly succeeded' then raise; end if;
    if position('authentication required' in sqlerrm) = 0 then raise; end if;
  end;

  if (select count(*) from public.sales) <> 2 then raise exception 'unauthorized sale changed sales'; end if;
  if (select count(*) from private.sale_idempotency_requests) <> 2 then
    raise exception 'unauthorized sale changed idempotency records';
  end if;
end;
$test$;
