-- Enforce full allocation of supplier payments.
-- Supplier payment totals are treated as settled account credits in supplier summaries,
-- so allowing an unallocated remainder would understate the supplier balance.
-- Also reject empty allocation lists.

create or replace function private.record_supplier_payment(
  p_organization_id uuid,
  p_store_id uuid,
  p_supplier_id bigint,
  p_amount numeric,
  p_payment_method text default 'cash',
  p_reference text default null,
  p_notes text default null,
  p_allocations jsonb default '[]'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_payment_id bigint;
  v_item jsonb;
  v_receipt public.purchase_receipts;
  v_receipt_id bigint;
  v_alloc numeric;
  v_existing numeric;
  v_total_allocated numeric := 0;
  v_new_allocated numeric;
  v_status text;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'organization/store access denied'; end if;
  if not private.has_org_permission(p_organization_id,'supplier_payments.create') then raise exception 'supplier_payments.create permission required'; end if;
  if p_supplier_id is null then raise exception 'supplier is required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'payment amount must be greater than zero'; end if;
  if jsonb_typeof(p_allocations) <> 'array' or jsonb_array_length(p_allocations) = 0 then raise exception 'at least one supplier payment allocation is required'; end if;
  if not exists (select 1 from public.suppliers where id=p_supplier_id and organization_id=p_organization_id) then raise exception 'supplier not found'; end if;
  if exists (select 1 from jsonb_array_elements(p_allocations) x group by (x->>'purchase_receipt_id') having count(*) > 1) then raise exception 'duplicate purchase allocation lines are not allowed'; end if;

  insert into public.supplier_payments(organization_id,store_id,supplier_id,amount,payment_method,reference,notes)
  values(p_organization_id,p_store_id,p_supplier_id,p_amount,coalesce(nullif(btrim(p_payment_method),''),'cash'),nullif(btrim(coalesce(p_reference,'')),''),nullif(btrim(coalesce(p_notes,'')),''))
  returning id into v_payment_id;

  for v_item in select value from jsonb_array_elements(p_allocations) loop
    v_receipt_id := (v_item->>'purchase_receipt_id')::bigint;
    v_alloc := (v_item->>'amount')::numeric;
    if v_receipt_id is null or v_alloc is null or v_alloc <= 0 then raise exception 'invalid supplier payment allocation'; end if;

    select * into v_receipt
    from public.purchase_receipts
    where id=v_receipt_id
      and organization_id=p_organization_id
      and store_id=p_store_id
      and supplier_id=p_supplier_id
      and status='completed'
    for update;
    if not found then raise exception 'purchase receipt not found for supplier/store'; end if;

    select coalesce(sum(amount),0) into v_existing
    from public.supplier_payment_allocations
    where purchase_receipt_id=v_receipt_id and organization_id=p_organization_id;
    if v_existing + v_alloc > v_receipt.total then raise exception 'allocation exceeds purchase remaining balance'; end if;

    v_total_allocated := v_total_allocated + v_alloc;
    insert into public.supplier_payment_allocations(organization_id,supplier_payment_id,purchase_receipt_id,amount)
    values(p_organization_id,v_payment_id,v_receipt_id,v_alloc);

    v_new_allocated := v_existing + v_alloc;
    v_status := case when v_new_allocated >= v_receipt.total then 'paid' else 'partial' end;
    update public.purchase_receipts set payment_status=v_status where id=v_receipt_id and organization_id=p_organization_id;
  end loop;

  if v_total_allocated <> p_amount then raise exception 'payment amount must equal allocated amount'; end if;

  perform private.write_audit_log(
    p_organization_id,p_store_id,'supplier.payment_recorded','supplier_payment',v_payment_id::text,
    jsonb_build_object('supplier_id',p_supplier_id,'amount',p_amount,'allocated',v_total_allocated,'unallocated',0)
  );

  return jsonb_build_object('id',v_payment_id,'amount',p_amount,'allocated',v_total_allocated,'unallocated',0);
exception
  when unique_violation then raise exception 'duplicate supplier payment allocation';
end;
$function$;
