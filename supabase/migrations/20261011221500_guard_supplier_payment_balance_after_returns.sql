-- Prevent supplier payments from exceeding the purchase balance after returns/refunds.
-- Function-definition-only migration: no financial rows are rewritten.
do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
  v_occurrences integer;
begin
  v_def := pg_get_functiondef(
    'private.record_supplier_payment(uuid,uuid,bigint,numeric,text,text,text,jsonb)'::regprocedure
  );

  -- Match the canonical formatting returned by pg_get_functiondef, not a flattened declaration.
  v_old := $old$  v_payment_id bigint;
  v_item jsonb;
  v_receipt public.purchase_receipts;
  v_receipt_id bigint;
  v_alloc numeric;
  v_existing numeric;
  v_total_allocated numeric := 0;
  v_new_allocated numeric;
  v_status text;$old$;
  v_new := $new$  v_payment_id bigint;
  v_item jsonb;
  v_receipt public.purchase_receipts;
  v_receipt_id bigint;
  v_alloc numeric;
  v_existing numeric;
  v_total_allocated numeric := 0;
  v_new_allocated numeric;
  v_status text;
  v_return_total numeric := 0;
  v_refund_total numeric := 0;
  v_net_balance numeric := 0;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'Expected one record_supplier_payment declaration pattern; found %', v_occurrences;
  end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$    select coalesce(sum(amount),0) into v_existing
    from public.supplier_payment_allocations
    where purchase_receipt_id=v_receipt_id and organization_id=p_organization_id;
    if v_existing + v_alloc > v_receipt.total then raise exception 'allocation exceeds purchase remaining balance'; end if;$old$;
  v_new := $new$    select coalesce(sum(amount),0) into v_existing
    from public.supplier_payment_allocations
    where purchase_receipt_id=v_receipt_id and organization_id=p_organization_id;
    select coalesce(sum(pr.total),0) into v_return_total
    from public.purchase_returns pr
    where pr.purchase_receipt_id=v_receipt_id
      and pr.organization_id=p_organization_id
      and pr.status='completed';
    select coalesce(sum(sr.amount),0) into v_refund_total
    from public.supplier_refunds sr
    join public.purchase_returns pr on pr.id=sr.purchase_return_id
    where pr.purchase_receipt_id=v_receipt_id
      and pr.organization_id=p_organization_id
      and pr.status='completed';
    -- Keep the cap consistent with the supplier ledger: purchases - allocations - returns + refunds.
    v_net_balance := greatest(v_receipt.total - v_return_total + v_refund_total, 0);
    if v_existing + v_alloc > v_net_balance then raise exception 'allocation exceeds purchase remaining balance after returns and refunds'; end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'Expected one supplier balance validation pattern; found %', v_occurrences;
  end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$    v_new_allocated := v_existing + v_alloc;
    v_status := case when v_new_allocated >= v_receipt.total then 'paid' else 'partial' end;$old$;
  v_new := $new$    v_new_allocated := v_existing + v_alloc;
    v_status := case when v_new_allocated >= v_net_balance then 'paid' else 'partial' end;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'Expected one supplier payment status pattern; found %', v_occurrences;
  end if;
  v_def := replace(v_def, v_old, v_new);

  execute v_def;
end;
$migration$;
