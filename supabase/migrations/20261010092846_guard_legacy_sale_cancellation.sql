-- The legacy 3-argument cancellation overload previously restored stock and marked a sale
-- cancelled without refunding payments or restoring historical inventory cost.
-- Keep compatibility for unpaid sales only; paid/refunded sales must use the
-- refund-aware 5-argument overload.
create or replace function private.cancel_sale(
  p_organization_id uuid,
  p_sale_id bigint,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private'
as $function$
declare
  v_sale public.sales%rowtype;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if p_organization_id is null or p_sale_id is null then
    raise exception 'organization_id and sale_id are required';
  end if;

  select *
    into v_sale
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

  if exists (select 1 from public.payments p where p.sale_id = v_sale.id)
     or exists (select 1 from public.refunds r where r.sale_id = v_sale.id) then
    raise exception 'paid or refunded sales must use the refund-aware cancellation workflow';
  end if;

  -- Delegate to the current implementation so inventory cost tracking, audit logging,
  -- and cancellation invariants remain identical to the refund-aware workflow.
  return private.cancel_sale(
    p_organization_id,
    p_sale_id,
    p_reason,
    'cash',
    null
  );
end;
$function$;
