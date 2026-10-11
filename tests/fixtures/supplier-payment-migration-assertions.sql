do $test$
declare
  v_result jsonb;
  v_message text;
  v_failed boolean;
  v_total numeric;
  v_status text;
begin
  if not exists (select 1 from public.suppliers where id=1) then
    insert into public.suppliers(id,organization_id)
    values (1,'00000000-0000-0000-0000-000000000001');
  end if;

  insert into public.purchase_receipts(id,organization_id,store_id,supplier_id,status,total,payment_status) values
    (1,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'partial'),
    (2,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'partial'),
    (3,'00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',1,'completed',100,'unpaid');
  insert into public.purchase_returns(id,organization_id,purchase_receipt_id,status,total) values
    (11,'00000000-0000-0000-0000-000000000001',1,'completed',20),
    (12,'00000000-0000-0000-0000-000000000001',2,'completed',20),
    (13,'00000000-0000-0000-0000-000000000001',3,'completed',120);
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
  raise notice 'supplier payment migration integration assertions passed';
end;
$test$;
