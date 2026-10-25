-- Read-only purchase return history with the same organization/store and permission checks
-- used by purchase_return_details. This avoids exposing return history through broad table RLS.
create or replace function private.purchase_return_history(
  p_organization_id uuid,
  p_store_id uuid,
  p_purchase_receipt_id bigint
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'private'
as $$
declare
  v_purchase public.purchase_receipts%rowtype;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  if not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'organization/store access denied';
  end if;
  if not private.has_org_permission(p_organization_id, 'purchases.view') then
    raise exception 'purchases.view permission required';
  end if;

  select *
    into v_purchase
    from public.purchase_receipts
   where id = p_purchase_receipt_id
     and organization_id = p_organization_id
     and store_id = p_store_id;

  if not found then
    raise exception 'purchase receipt not found';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'returnNumber', r.return_number,
        'purchaseReceiptId', r.purchase_receipt_id,
        'total', r.total,
        'refundAmount', r.refund_amount,
        'refundPaymentMethod', r.refund_payment_method,
        'refundReference', r.refund_reference,
        'reason', r.reason,
        'notes', r.notes,
        'status', r.status,
        'createdAt', r.created_at,
        'items', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', ri.id,
              'purchaseReceiptItemId', ri.purchase_receipt_item_id,
              'productId', ri.product_id,
              'productName', p.name,
              'quantity', ri.quantity,
              'unitCost', ri.unit_cost,
              'total', ri.total
            )
            order by ri.id
          )
          from public.purchase_return_items ri
          join public.products p on p.id = ri.product_id
          where ri.purchase_return_id = r.id
        ), '[]'::jsonb)
      )
      order by r.created_at desc, r.id desc
    )
    from public.purchase_returns r
    where r.organization_id = p_organization_id
      and r.store_id = p_store_id
      and r.purchase_receipt_id = v_purchase.id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.purchase_return_history(
  p_organization_id uuid,
  p_store_id uuid,
  p_purchase_receipt_id bigint
) returns jsonb
language plpgsql
security invoker
set search_path = 'public', 'private'
as $$
begin
  return private.purchase_return_history(
    p_organization_id,
    p_store_id,
    p_purchase_receipt_id
  );
end;
$$;

revoke execute on function public.purchase_return_history(uuid, uuid, bigint) from public, anon;
grant execute on function public.purchase_return_history(uuid, uuid, bigint) to authenticated;
