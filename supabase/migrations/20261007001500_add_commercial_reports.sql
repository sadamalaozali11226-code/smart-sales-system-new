create or replace function private.commercial_reports(
  p_organization_id uuid,
  p_store_id uuid default null,
  p_from_date date default null,
  p_to_date date default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_store_id is null then
    if not exists (
      select 1 from public.organization_members om
      where om.organization_id = p_organization_id
        and om.user_id = (select auth.uid())
        and om.status = 'active'
    ) then
      raise exception 'Organization access denied';
    end if;
  elsif not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'Store access denied';
  end if;

  if p_from_date is not null and p_to_date is not null and p_from_date > p_to_date then
    raise exception 'Invalid date range';
  end if;

  v_result := jsonb_build_object(
    'sales', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select s.id,s.invoice_number,coalesce(c.name,'نقدي') as customer_name,
               s.total,s.payment_status,s.status,s.created_at
        from public.sales s
        left join public.customers c on c.id=s.customer_id
        where s.organization_id=p_organization_id
          and (p_store_id is null or s.store_id=p_store_id)
          and s.status <> 'cancelled'
          and (p_from_date is null or s.created_at >= p_from_date::timestamptz)
          and (p_to_date is null or s.created_at < (p_to_date+1)::timestamptz)
        order by s.created_at desc limit 200
      ) x
    ),'[]'::jsonb),
    'purchases', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select pr.id,pr.receipt_number,pr.supplier_invoice_number,
               coalesce(sp.name,'-') as supplier_name,pr.total,
               pr.payment_status,pr.status,pr.created_at
        from public.purchase_receipts pr
        left join public.suppliers sp on sp.id=pr.supplier_id
        where pr.organization_id=p_organization_id
          and (p_store_id is null or pr.store_id=p_store_id)
          and pr.status <> 'cancelled'
          and (p_from_date is null or pr.created_at >= p_from_date::timestamptz)
          and (p_to_date is null or pr.created_at < (p_to_date+1)::timestamptz)
        order by pr.created_at desc limit 200
      ) x
    ),'[]'::jsonb),
    'inventory', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.quantity asc,x.product_name)
      from (
        select sp.product_id,p.name as product_name,sp.quantity,sp.reorder_level,
               sp.average_cost,(sp.quantity*coalesce(sp.average_cost,0))::numeric as stock_value
        from public.store_products sp
        join public.products p on p.id=sp.product_id
        where sp.store_id=p_store_id and p.organization_id=p_organization_id
        order by sp.quantity asc,p.name limit 500
      ) x
    ),'[]'::jsonb),
    'customers', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.balance desc,x.customer_name)
      from (
        select * from private.customer_account_summary(p_organization_id,p_store_id)
        where balance <> 0 order by balance desc,customer_name limit 200
      ) x
    ),'[]'::jsonb),
    'suppliers', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.balance desc,x.supplier_name)
      from (
        select * from private.supplier_account_summary(p_organization_id,p_store_id)
        where balance <> 0 order by balance desc,supplier_name limit 200
      ) x
    ),'[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.expense_date desc,x.id desc)
      from (
        select e.id,e.expense_number,e.category,e.amount,e.expense_date,
               e.payment_method,e.status,e.created_at
        from public.expenses e
        where e.organization_id=p_organization_id
          and (p_store_id is null or e.store_id=p_store_id)
          and (p_from_date is null or e.expense_date>=p_from_date)
          and (p_to_date is null or e.expense_date<=p_to_date)
        order by e.expense_date desc,e.id desc limit 200
      ) x
    ),'[]'::jsonb),
    'movements', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select im.id,p.name as product_name,im.movement_type,im.quantity_change,
               im.reference_type,im.reference_id,im.notes,im.created_at
        from public.inventory_movements im
        left join public.products p on p.id=im.product_id
        where im.organization_id=p_organization_id
          and (p_store_id is null or im.store_id=p_store_id)
          and (p_from_date is null or im.created_at>=p_from_date::timestamptz)
          and (p_to_date is null or im.created_at<(p_to_date+1)::timestamptz)
        order by im.created_at desc limit 300
      ) x
    ),'[]'::jsonb),
    'transfers', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select st.id,p.name as product_name,sf.name as from_store_name,
               stt.name as to_store_name,st.quantity,st.created_at,st.notes
        from public.stock_transfers st
        join public.products p on p.id=st.product_id
        join public.stores sf on sf.id=st.from_store_id
        join public.stores stt on stt.id=st.to_store_id
        where st.organization_id=p_organization_id
          and (p_store_id is null or st.from_store_id=p_store_id or st.to_store_id=p_store_id)
          and (p_from_date is null or st.created_at>=p_from_date::timestamptz)
          and (p_to_date is null or st.created_at<(p_to_date+1)::timestamptz)
        order by st.created_at desc limit 200
      ) x
    ),'[]'::jsonb)
  );

  return v_result;
end;
$function$;

revoke all on function private.commercial_reports(uuid,uuid,date,date) from public;
grant execute on function private.commercial_reports(uuid,uuid,date,date) to authenticated;

create or replace function public.commercial_reports(
  p_organization_id uuid,
  p_store_id uuid default null,
  p_from_date date default null,
  p_to_date date default null
)
returns jsonb
language sql
security invoker
set search_path=''
as $function$
  select private.commercial_reports(p_organization_id,p_store_id,p_from_date,p_to_date);
$function$;

revoke all on function public.commercial_reports(uuid,uuid,date,date) from public;
grant execute on function public.commercial_reports(uuid,uuid,date,date) to authenticated;
