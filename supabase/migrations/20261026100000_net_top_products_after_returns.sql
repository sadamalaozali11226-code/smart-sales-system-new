-- Report product sales net of item-level returns.
-- This changes the report function only; it does not modify sales or return records.
-- Guard the expected query fragment so an unexpected function definition fails safely.

do $migration$
declare
  v_definition text;
  v_old_fragment constant text := $old$
from (select si.product_id, max(si.product_name) product_name, sum(si.quantity) quantity, sum(si.total) sales_total from public.sale_items si join public.sales s on s.id=si.sale_id where s.organization_id=p_organization_id and (p_store_id is null or s.store_id=p_store_id) and s.status in ('completed','partially_returned','fully_returned') and (v_from is null or s.created_at >= v_from) and (v_to is null or s.created_at < v_to) group by si.product_id order by sum(si.total) desc limit 10) x)
$old$;
  v_new_fragment constant text := $new$
from (
  select
    si.product_id,
    max(si.product_name) product_name,
    sum(si.quantity - coalesce(ri.quantity, 0)) quantity,
    sum(si.total - coalesce(ri.refund_amount, 0)) sales_total
  from public.sale_items si
  join public.sales s on s.id=si.sale_id
  left join (
    select
      sri.sale_item_id,
      sum(sri.quantity) quantity,
      sum(sri.refund_amount) refund_amount
    from public.sale_return_items sri
    join public.sale_returns sr on sr.id=sri.return_id
    where sr.organization_id=p_organization_id
      and (p_store_id is null or sr.store_id=p_store_id)
      and (v_from is null or sr.created_at >= v_from)
      and (v_to is null or sr.created_at < v_to)
    group by sri.sale_item_id
  ) ri on ri.sale_item_id=si.id
  where s.organization_id=p_organization_id
    and (p_store_id is null or s.store_id=p_store_id)
    and s.status in ('completed','partially_returned','fully_returned')
    and (v_from is null or s.created_at >= v_from)
    and (v_to is null or s.created_at < v_to)
  group by si.product_id
  having sum(si.quantity - coalesce(ri.quantity, 0)) > 0
  order by sum(si.total - coalesce(ri.refund_amount, 0)) desc
  limit 10
) x)
$new$;
  v_occurrences integer;
begin
  select pg_get_functiondef(
    'private.commercial_reports_summary(uuid,uuid,date,date)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'Expected function private.commercial_reports_summary(uuid,uuid,date,date) was not found';
  end if;

  v_occurrences :=
    (length(v_definition) - length(replace(v_definition, v_old_fragment, '')))
    / length(v_old_fragment);

  if v_occurrences <> 1 then
    raise exception 'Expected one top_products query fragment; found %; no change applied', v_occurrences;
  end if;

  v_definition := replace(v_definition, v_old_fragment, v_new_fragment);

  if position('sum(sri.refund_amount)' in v_definition) = 0
     or position('sum(sri.quantity)' in v_definition) = 0 then
    raise exception 'Validation failed for net top_products query; no change applied';
  end if;

  execute v_definition;
end;
$migration$;
