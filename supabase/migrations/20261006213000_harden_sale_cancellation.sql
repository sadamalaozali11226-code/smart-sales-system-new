create or replace function private.cancel_sale(
  p_organization_id uuid,
  p_sale_id bigint,
  p_reason text default null,
  p_refund_payment_method text default 'cash',
  p_refund_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public','private'
as $function$
declare
  v_sale public.sales%rowtype;
  v_item record;
  v_balance public.store_products%rowtype;
  v_restored numeric := 0;
  v_reason text;
  v_refund_method text;
  v_refund_reference text;
  v_paid numeric := 0;
  v_refunded numeric := 0;
  v_refundable numeric := 0;
  v_refund_id bigint;
  v_audit_id bigint;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_organization_id is null or p_sale_id is null then
    raise exception 'organization_id and sale_id are required';
  end if;

  select * into v_sale
  from public.sales s
  where s.id = p_sale_id
    and s.organization_id = p_organization_id
  for update;

  if not found then
    raise exception 'sale not found';
  end if;

  if not private.is_org_store_member(p_organization_id, v_sale.store_id) then
    raise exception 'not authorized for this sale';
  end if;

  if not private.has_org_permission(p_organization_id, 'sales.cancel') then
    raise exception 'missing permission: sales.cancel';
  end if;

  if v_sale.status <> 'completed' then
    raise exception 'only completed sales can be cancelled; process returned sales through the return workflow';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if v_reason is null then
    raise exception 'cancellation reason is required';
  end if;

  select coalesce(sum(p.amount), 0)
    into v_paid
  from public.payments p
  where p.sale_id = v_sale.id;

  select coalesce(sum(r.amount), 0)
    into v_refunded
  from public.refunds r
  where r.sale_id = v_sale.id;

  v_refundable := v_paid - v_refunded;
  if v_refundable < 0 then
    raise exception 'sale refund state is invalid';
  end if;

  if v_refundable > 0 then
    if not private.has_org_permission(p_organization_id, 'payments.refund') then
      raise exception 'missing permission: payments.refund';
    end if;

    v_refund_method := nullif(btrim(coalesce(p_refund_payment_method, '')), '');
    if v_refund_method is null then
      raise exception 'refund payment method is required for a paid sale';
    end if;

    v_refund_reference := nullif(btrim(coalesce(p_refund_reference, '')), '');

    insert into public.refunds (
      sale_id, organization_id, store_id, amount, payment_method, reference, reason
    )
    values (
      v_sale.id, v_sale.organization_id, v_sale.store_id,
      v_refundable, v_refund_method, v_refund_reference,
      'Sale cancellation: ' || v_reason
    )
    returning id into v_refund_id;

    perform private.write_audit_log(
      v_sale.organization_id,
      v_sale.store_id,
      'payment.refunded',
      'refund',
      v_refund_id::text,
      jsonb_build_object(
        'sale_id', v_sale.id,
        'invoice_number', v_sale.invoice_number,
        'amount', v_refundable,
        'payment_method', v_refund_method,
        'reference', v_refund_reference,
        'reason', 'Sale cancellation: ' || v_reason,
        'remaining_refundable', 0
      )
    );
  end if;

  for v_item in
    select si.product_id, si.quantity
    from public.sale_items si
    where si.sale_id = v_sale.id
      and si.product_id is not null
    order by si.product_id
  loop
    select * into v_balance
    from public.store_products
    where store_id = v_sale.store_id
      and product_id = v_item.product_id
    for update;

    if not found then
      raise exception 'product is not assigned to the sale store; cancellation aborted';
    end if;

    update public.store_products
       set quantity = quantity + v_item.quantity,
           updated_at = now()
     where id = v_balance.id;

    insert into public.inventory_movements (
      product_id, organization_id, store_id, movement_type,
      quantity_change, reference_type, reference_id, notes
    )
    values (
      v_item.product_id, p_organization_id, v_sale.store_id, 'return',
      v_item.quantity, 'sale_cancellation', v_sale.id,
      'Stock restored by sale cancellation: ' || v_reason
    );

    v_restored := v_restored + v_item.quantity;
  end loop;

  update public.sales
     set status = 'cancelled',
         notes = case
           when nullif(btrim(coalesce(notes, '')), '') is null
             then 'Cancelled: ' || v_reason
           else notes || E'\nCancelled: ' || v_reason
         end
   where id = v_sale.id;

  v_audit_id := private.write_audit_log(
    p_organization_id,
    v_sale.store_id,
    'sale.cancelled',
    'sale',
    v_sale.id::text,
    jsonb_build_object(
      'invoice_number', v_sale.invoice_number,
      'restored_quantity', v_restored,
      'paid_amount', v_paid,
      'previously_refunded', v_refunded,
      'refund_amount', v_refundable,
      'refund_id', v_refund_id,
      'reason', v_reason
    )
  );

  return jsonb_build_object(
    'sale_id', v_sale.id,
    'status', 'cancelled',
    'restored_quantity', v_restored,
    'paid_amount', v_paid,
    'refund_amount', v_refundable,
    'refund_id', v_refund_id,
    'audit_log_id', v_audit_id
  );
end;
$function$;

create or replace function public.cancel_sale(
  p_organization_id uuid,
  p_sale_id bigint,
  p_reason text default null,
  p_refund_payment_method text default 'cash',
  p_refund_reference text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = 'public','private'
as $function$
begin
  return private.cancel_sale(
    p_organization_id,
    p_sale_id,
    p_reason,
    p_refund_payment_method,
    p_refund_reference
  );
end;
$function$;

revoke execute on function public.cancel_sale(uuid,bigint,text) from public, anon;
revoke execute on function public.cancel_sale(uuid,bigint,text,text,text) from public, anon;
grant execute on function public.cancel_sale(uuid,bigint,text,text,text) to authenticated;
