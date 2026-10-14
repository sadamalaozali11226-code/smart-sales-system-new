do $test$
declare
  v_result jsonb;
  v_message text;
  v_failed boolean;
  v_total numeric;
  v_status text;
  v_count_before bigint;
  v_count_after bigint;
begin
  if not exists (select 1 from public.suppliers where id=1) then
    insert into public.suppliers(id,organization_id)
    values (1,'00000000-0000-0000-0000-000000000001');
  end if;

  insert into public.purchase_receipts(id,organization_id,store_id,supplier_id,status,total,payment_status) values
    (1,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'partial'),
    (2,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'partial'),
    (3,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'unpaid'),
    (4,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'unpaid'),
    (5,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'unpaid');
  insert into public.purchase_returns(id,organization_id,purchase_receipt_id,status,total) values
    (11,'00000000-0000-0000-0000-000000000001',1,'completed',20),
    (12,'00000000-0000-0000-0000-000000000001',2,'completed',20),
    (13,'00000000-0000-0000-0000-000000000001',3,'completed',120),
    (14,'00000000-0000-0000-0000-000000000001',4,'pending',90);
  insert into public.supplier_refunds(id,purchase_return_id,amount) values
    (21,11,10);

  insert into public.supplier_payments(id,organization_id,store_id,supplier_id,amount,payment_method)
  values
    (100,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,80,'cash'),
    (101,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,80,'cash');
  perform setval(pg_get_serial_sequence('public.supplier_payments','id'),101,true);
  insert into public.supplier_payment_allocations(organization_id,supplier_payment_id,purchase_receipt_id,amount) values
    ('00000000-0000-0000-0000-000000000001',100,1,80),
    ('00000000-0000-0000-0000-000000000001',101,2,80);

  -- Completed return plus partial refund: 100 - 20 + 10 = 90 available.
  v_result := private.record_supplier_payment(
    '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
    1,10,'cash',null,null,'[{"purchase_receipt_id":1,"amount":10}]'::jsonb
  );
  if (v_result->>'allocated')::numeric <> 10 then
    raise exception 'Expected successful allocation of 10, got %', v_result;
  end if;
  select sum(amount) into v_total from public.supplier_payment_allocations where purchase_receipt_id=1;
  if v_total <> 90 then raise exception 'Expected receipt 1 allocation total 90, got %', v_total; end if;
  select payment_status into v_status from public.purchase_receipts where id=1;
  if v_status <> 'paid' then raise exception 'Expected receipt 1 status paid, got %', v_status; end if;

  -- A completed return with no refund reduces the ceiling to 80.
  v_failed := false;
  begin
    perform private.record_supplier_payment(
      '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
      1,1,'cash',null,null,'[{"purchase_receipt_id":2,"amount":1}]'::jsonb
    );
  exception when others then
    get stacked diagnostics v_message = message_text;
    if position('allocation exceeds purchase remaining balance after returns and refunds' in v_message)=0 then
      raise;
    end if;
    v_failed := true;
  end;
  if not v_failed then raise exception 'Expected allocation above the net return-adjusted balance to fail'; end if;
  select sum(amount) into v_total from public.supplier_payment_allocations where purchase_receipt_id=2;
  if v_total <> 80 then raise exception 'Failed allocation changed receipt 2 total to %', v_total; end if;

  -- Returns exceeding the purchase total must clamp the payment ceiling at zero.
  v_failed := false;
  begin
    perform private.record_supplier_payment(
      '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
      1,1,'cash',null,null,'[{"purchase_receipt_id":3,"amount":1}]'::jsonb
    );
  exception when others then
    get stacked diagnostics v_message = message_text;
    if position('allocation exceeds purchase remaining balance after returns and refunds' in v_message)=0 then
      raise;
    end if;
    v_failed := true;
  end;
  if not v_failed then raise exception 'Expected a fully-returned purchase to reject further allocation'; end if;

  -- Pending returns must not reduce the balance until they are completed.
  v_result := private.record_supplier_payment(
    '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
    1,100,'cash',null,null,'[{"purchase_receipt_id":4,"amount":100}]'::jsonb
  );
  if (v_result->>'allocated')::numeric <> 100 then
    raise exception 'Expected pending return to leave full balance available, got %', v_result;
  end if;
  select payment_status into v_status from public.purchase_receipts where id=4;
  if v_status <> 'paid' then raise exception 'Expected receipt 4 status paid while return is pending, got %', v_status; end if;

  -- A mismatch between payment amount and allocations must roll back the payment,
  -- allocation, and status update as one atomic operation.
  select count(*) into v_count_before from public.supplier_payments;
  v_failed := false;
  begin
    perform private.record_supplier_payment(
      '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
      1,10,'cash',null,null,'[{"purchase_receipt_id":5,"amount":5}]'::jsonb
    );
  exception when others then
    get stacked diagnostics v_message = message_text;
    if position('payment amount must equal allocated amount' in v_message)=0 then
      raise;
    end if;
    v_failed := true;
  end;
  if not v_failed then raise exception 'Expected payment/allocation mismatch to fail'; end if;
  select count(*) into v_count_after from public.supplier_payments;
  if v_count_after <> v_count_before then
    raise exception 'Failed payment left a supplier payment row behind: before %, after %', v_count_before, v_count_after;
  end if;
  if exists (select 1 from public.supplier_payment_allocations where purchase_receipt_id=5) then
    raise exception 'Failed payment left an allocation behind';
  end if;
  select payment_status into v_status from public.purchase_receipts where id=5;
  if v_status <> 'unpaid' then raise exception 'Failed payment changed receipt 5 status to %', v_status; end if;

  -- Duplicate allocation lines must be rejected before creating a payment.
  select count(*) into v_count_before from public.supplier_payments;
  v_failed := false;
  begin
    perform private.record_supplier_payment(
      '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',
      1,10,'cash',null,null,'[{"purchase_receipt_id":5,"amount":5},{"purchase_receipt_id":5,"amount":5}]'::jsonb
    );
  exception when others then
    get stacked diagnostics v_message = message_text;
    if position('duplicate purchase allocation lines are not allowed' in v_message)=0 then
      raise;
    end if;
    v_failed := true;
  end;
  if not v_failed then raise exception 'Expected duplicate allocation lines to fail'; end if;
  select count(*) into v_count_after from public.supplier_payments;
  if v_count_after <> v_count_before then
    raise exception 'Duplicate allocation attempt created a supplier payment row';
  end if;

  raise notice 'supplier payment migration integration assertions passed';
end;
$test$;
