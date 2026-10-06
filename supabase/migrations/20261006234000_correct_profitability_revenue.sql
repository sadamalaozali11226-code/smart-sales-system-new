-- Correct profitability revenue basis: invoice totals, not line subtotals
create or replace function private.profitability_summary(
  p_organization_id uuid,
  p_store_id uuid default null,
  p_from_date date default null,
  p_to_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_gross_sales numeric := 0;
  v_sales_tax numeric := 0;
  v_sales_discount numeric := 0;
  v_net_sales numeric := 0;
  v_cogs numeric := 0;
  v_return_sales numeric := 0;
  v_return_cogs numeric := 0;
  v_expenses numeric := 0;
  v_unknown_cost_qty numeric := 0;
  v_unknown_cost_items integer := 0;
  v_sale_item_count integer := 0;
  v_return_item_count integer := 0;
  v_gross_profit numeric := 0;
  v_net_profit numeric := 0;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=v_uid) then
    raise exception 'Organization access denied';
  end if;
  if p_from_date is not null and p_to_date is not null and p_from_date > p_to_date then raise exception 'Invalid date range'; end if;
  if p_store_id is not null and not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'Store access denied'; end if;

  with eligible_sales as (
    select s.id,s.total,s.tax,s.discount
    from public.sales s
    where s.organization_id=p_organization_id and s.status='completed'
      and (p_store_id is null or s.store_id=p_store_id)
      and (p_from_date is null or s.created_at::date>=p_from_date)
      and (p_to_date is null or s.created_at::date<=p_to_date)
  ), sale_costs as (
    select si.id,si.quantity,si.unit_cost,si.cost_total
    from public.sale_items si join eligible_sales es on es.id=si.sale_id
  ), returned as (
    select sri.return_id,sr.sale_id,sri.quantity,sri.refund_amount,sri.sale_item_id
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id=sri.return_id and sr.status='completed'
    join eligible_sales es on es.id=sr.sale_id
  )
  select
    coalesce((select sum(total) from eligible_sales),0),
    coalesce((select sum(tax) from eligible_sales),0),
    coalesce((select sum(discount) from eligible_sales),0),
    coalesce((select sum(cost_total) from sale_costs where unit_cost is not null),0),
    coalesce((select sum(refund_amount) from returned),0),
    coalesce((select sum(si.unit_cost*r.quantity) from returned r join public.sale_items si on si.id=r.sale_item_id where si.unit_cost is not null),0),
    coalesce((select count(*) from sale_costs where unit_cost is null),0),
    coalesce((select count(*) from sale_costs),0),
    coalesce((select count(*) from returned),0),
    coalesce((select sum(quantity) from sale_costs where unit_cost is null),0)
  into v_gross_sales,v_sales_tax,v_sales_discount,v_cogs,v_return_sales,v_return_cogs,
       v_unknown_cost_items,v_sale_item_count,v_return_item_count,v_unknown_cost_qty;

  select coalesce(sum(amount),0) into v_expenses
  from public.expenses
  where organization_id=p_organization_id and status='completed'
    and (p_store_id is null or store_id=p_store_id)
    and (p_from_date is null or expense_date>=p_from_date)
    and (p_to_date is null or expense_date<=p_to_date);

  v_net_sales:=v_gross_sales-v_return_sales;
  v_cogs:=greatest(v_cogs-v_return_cogs,0);
  v_gross_profit:=v_net_sales-v_cogs;
  v_net_profit:=v_gross_profit-v_expenses;

  return jsonb_build_object(
    'gross_sales',round(v_gross_sales,2),'sales_returns',round(v_return_sales,2),'net_sales',round(v_net_sales,2),
    'sales_tax',round(v_sales_tax,2),'sales_discount',round(v_sales_discount,2),'cogs',round(v_cogs,2),
    'return_cogs',round(v_return_cogs,2),'gross_profit',round(v_gross_profit,2),'expenses',round(v_expenses,2),
    'net_profit',round(v_net_profit,2),
    'gross_margin_percent',case when v_net_sales>0 then round(v_gross_profit/v_net_sales*100,2) else 0 end,
    'net_margin_percent',case when v_net_sales>0 then round(v_net_profit/v_net_sales*100,2) else 0 end,
    'cost_coverage_percent',case when v_sale_item_count>0 then round((v_sale_item_count-v_unknown_cost_items)::numeric/v_sale_item_count*100,2) else 100 end,
    'unknown_cost_items',v_unknown_cost_items,'unknown_cost_quantity',v_unknown_cost_qty,
    'sale_item_count',v_sale_item_count,'return_item_count',v_return_item_count,
    'warning',case when v_unknown_cost_items>0 then 'Some sales have no historical cost snapshot; profitability is incomplete for those items.' else null end,
    'from_date',p_from_date,'to_date',p_to_date,'store_id',p_store_id
  );
end;
$$;

revoke all on function private.profitability_summary(uuid,uuid,date,date) from public,anon,authenticated;
revoke all on function public.profitability_summary(uuid,uuid,date,date) from public,anon;
grant execute on function public.profitability_summary(uuid,uuid,date,date) to authenticated;