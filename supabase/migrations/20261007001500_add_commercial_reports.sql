-- Corrected commercial reporting dashboard RPC.
-- The previous commercial_reports RPC remains for compatibility.
-- This migration adds the richer, read-only, organization/store-authorized summary used by the app.

create or replace function public.commercial_reports_summary(
  p_organization_id uuid,
  p_store_id uuid default null,
  p_from_date date default null,
  p_to_date date default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private
as $$
declare
  v_from timestamptz := case when p_from_date is null then null else p_from_date::timestamptz end;
  v_to timestamptz := case when p_to_date is null then null else (p_to_date + 1)::timestamptz end;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.status='active') then raise exception 'Organization access denied'; end if;
  if p_store_id is not null and not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'Store access denied'; end if;
  if p_from_date is not null and p_to_date is not null and p_from_date>p_to_date then raise exception 'Invalid date range'; end if;

  return jsonb_build_object(
    'period',jsonb_build_object('from',p_from_date,'to',p_to_date),
    'sales',jsonb_build_object(
      'count',coalesce((select count(*) from public.sales s where s.organization_id=p_organization_id and (p_store_id is null or s.store_id=p_store_id) and s.status='completed' and (v_from is null or s.created_at>=v_from) and (v_to is null or s.created_at<v_to)),0),
      'gross_total',coalesce((select sum(s.total) from public.sales s where s.organization_id=p_organization_id and (p_store_id is null or s.store_id=p_store_id) and s.status='completed' and (v_from is null or s.created_at>=v_from) and (v_to is null or s.created_at<v_to)),0),
      'returns_total',coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where r.organization_id=p_organization_id and (p_store_id is null or r.store_id=p_store_id) and s.status<>'cancelled' and (v_from is null or r.refunded_at>=v_from) and (v_to is null or r.refunded_at<v_to)),0),
      'payment_methods',coalesce((select jsonb_agg(jsonb_build_object('method',x.payment_method,'amount',x.amount) order by x.amount desc) from (select coalesce(p.payment_method,'other') payment_method,sum(p.amount) amount from public.payments p join public.sales s on s.id=p.sale_id where s.organization_id=p_organization_id and (p_store_id is null or s.store_id=p_store_id) and s.status='completed' and (v_from is null or s.created_at>=v_from) and (v_to is null or s.created_at<v_to) group by coalesce(p.payment_method,'other')) x),'[]'::jsonb),
      'top_products',coalesce((select jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales_total',x.sales_total) order by x.sales_total desc) from (select si.product_id,max(si.product_name) product_name,sum(si.quantity) quantity,sum(si.total) sales_total from public.sale_items si join public.sales s on s.id=si.sale_id where s.organization_id=p_organization_id and (p_store_id is null or s.store_id=p_store_id) and s.status='completed' and (v_from is null or s.created_at>=v_from) and (v_to is null or s.created_at<v_to) group by si.product_id order by sum(si.total) desc limit 10) x),'[]'::jsonb)
    ),
    'purchases',jsonb_build_object(
      'count',coalesce((select count(*) from public.purchase_receipts pr where pr.organization_id=p_organization_id and (p_store_id is null or pr.store_id=p_store_id) and pr.status<>'cancelled' and (v_from is null or pr.created_at>=v_from) and (v_to is null or pr.created_at<v_to)),0),
      'total',coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.organization_id=p_organization_id and (p_store_id is null or pr.store_id=p_store_id) and pr.status<>'cancelled' and (v_from is null or pr.created_at>=v_from) and (v_to is null or pr.created_at<v_to)),0),
      'returns_total',coalesce((select sum(pr.total) from public.purchase_returns pr where pr.organization_id=p_organization_id and (p_store_id is null or pr.store_id=p_store_id) and pr.status='completed' and (v_from is null or pr.created_at>=v_from) and (v_to is null or pr.created_at<v_to)),0),
      'top_suppliers',coalesce((select jsonb_agg(jsonb_build_object('supplier_id',x.supplier_id,'supplier_name',x.supplier_name,'total',x.total) order by x.total desc) from (select pr.supplier_id,max(su.name) supplier_name,sum(pr.total) total from public.purchase_receipts pr left join public.suppliers su on su.id=pr.supplier_id where pr.organization_id=p_organization_id and (p_store_id is null or pr.store_id=p_store_id) and pr.status<>'cancelled' and (v_from is null or pr.created_at>=v_from) and (v_to is null or pr.created_at<v_to) group by pr.supplier_id order by sum(pr.total) desc limit 10) x),'[]'::jsonb)
    ),
    'inventory',jsonb_build_object(
      'product_count',coalesce((select count(*) from public.store_products sp where (p_store_id is null or sp.store_id=p_store_id) and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)),0),
      'quantity_total',coalesce((select sum(sp.quantity) from public.store_products sp where (p_store_id is null or sp.store_id=p_store_id) and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)),0),
      'estimated_value',coalesce((select sum(sp.quantity*coalesce(sp.average_cost,0)) from public.store_products sp where (p_store_id is null or sp.store_id=p_store_id) and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)),0),
      'low_stock_count',coalesce((select count(*) from public.store_products sp where (p_store_id is null or sp.store_id=p_store_id) and sp.quantity<=sp.reorder_level and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)),0),
      'items',coalesce((select jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'reorder_level',x.reorder_level,'average_cost',x.average_cost,'estimated_value',x.estimated_value) order by x.quantity asc,x.product_name) from (select sp.product_id,max(p.name) product_name,sp.quantity,sp.reorder_level,coalesce(sp.average_cost,0) average_cost,sp.quantity*coalesce(sp.average_cost,0) estimated_value from public.store_products sp join public.products p on p.id=sp.product_id where (p_store_id is null or sp.store_id=p_store_id) and p.organization_id=p_organization_id group by sp.product_id,sp.quantity,sp.reorder_level,sp.average_cost) x),'[]'::jsonb)
    ),
    'customers',coalesce((select jsonb_agg(jsonb_build_object('customer_id',x.customer_id,'customer_name',x.customer_name,'sales_total',x.sales_total,'payments',x.payments,'refunds',x.refunds,'balance',x.balance) order by x.balance desc) from (select c.id customer_id,c.name customer_name,
      coalesce((select sum(s.total) from public.sales s where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id) and (v_from is null or s.created_at>=v_from) and (v_to is null or s.created_at<v_to)),0) sales_total,
      coalesce((select sum(pay.amount) from public.payments pay join public.sales s on s.id=pay.sale_id where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id) and (v_from is null or pay.paid_at>=v_from) and (v_to is null or pay.paid_at<v_to)),0)+coalesce((select sum(cp.amount) from public.customer_payments cp where cp.customer_id=c.id and cp.organization_id=p_organization_id and (p_store_id is null or cp.store_id=p_store_id) and (v_from is null or cp.paid_at>=v_from) and (v_to is null or cp.paid_at<v_to)),0) payments,
      coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where s.customer_id=c.id and r.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id) and (v_from is null or r.refunded_at>=v_from) and (v_to is null or r.refunded_at<v_to)),0) refunds,
      coalesce((select sum(s.total) from public.sales s where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0)-coalesce((select sum(pay.amount) from public.payments pay join public.sales s on s.id=pay.sale_id where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0)-coalesce((select sum(cp.amount) from public.customer_payments cp where cp.customer_id=c.id and cp.organization_id=p_organization_id and (p_store_id is null or cp.store_id=p_store_id)),0)-coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where s.customer_id=c.id and r.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id)),0) balance
      from public.customers c where c.organization_id=p_organization_id) x),'[]'::jsonb),
    'suppliers',coalesce((select jsonb_agg(jsonb_build_object('supplier_id',x.supplier_id,'supplier_name',x.supplier_name,'purchases_total',x.purchases_total,'payments',x.payments,'returns',x.returns,'refunds',x.refunds,'balance',x.balance) order by x.balance desc) from (select su.id supplier_id,su.name supplier_name,
      coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id) and (v_from is null or pr.created_at>=v_from) and (v_to is null or pr.created_at<v_to)),0) purchases_total,
      coalesce((select sum(sp.amount) from public.supplier_payments sp where sp.supplier_id=su.id and sp.organization_id=p_organization_id and (p_store_id is null or sp.store_id=p_store_id) and (v_from is null or sp.paid_at>=v_from) and (v_to is null or sp.paid_at<v_to)),0) payments,
      coalesce((select sum(pr.total) from public.purchase_returns pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status='completed' and (p_store_id is null or pr.store_id=p_store_id) and (v_from is null or pr.created_at>=v_from) and (v_to is null or pr.created_at<v_to)),0) returns,
      coalesce((select sum(sr.amount) from public.supplier_refunds sr where sr.supplier_id=su.id and sr.organization_id=p_organization_id and (p_store_id is null or sr.store_id=p_store_id) and (v_from is null or sr.created_at>=v_from) and (v_to is null or sr.created_at<v_to)),0) refunds,
      coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id)),0)-coalesce((select sum(sp.amount) from public.supplier_payments sp where sp.supplier_id=su.id and sp.organization_id=p_organization_id and (p_store_id is null or sp.store_id=p_store_id)),0)-coalesce((select sum(pr.total) from public.purchase_returns pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status='completed' and (p_store_id is null or pr.store_id=p_store_id)),0)+coalesce((select sum(sr.amount) from public.supplier_refunds sr where sr.supplier_id=su.id and sr.organization_id=p_organization_id and (p_store_id is null or sr.store_id=p_store_id)),0) balance
      from public.suppliers su where su.organization_id=p_organization_id) x),'[]'::jsonb),
    'expenses',jsonb_build_object(
      'total',coalesce((select sum(e.amount) from public.expenses e where e.organization_id=p_organization_id and (p_store_id is null or e.store_id=p_store_id) and e.status='completed' and (p_from_date is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date)),0),
      'count',coalesce((select count(*) from public.expenses e where e.organization_id=p_organization_id and (p_store_id is null or e.store_id=p_store_id) and e.status='completed' and (p_from_date is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date)),0),
      'by_category',coalesce((select jsonb_agg(jsonb_build_object('category',x.category,'amount',x.amount) order by x.amount desc) from (select e.category,sum(e.amount) amount from public.expenses e where e.organization_id=p_organization_id and (p_store_id is null or e.store_id=p_store_id) and e.status='completed' and (p_from_date is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date) group by e.category) x),'[]'::jsonb)
    ),
    'inventory_movements',coalesce((select jsonb_agg(jsonb_build_object('movement_type',x.movement_type,'quantity',x.quantity,'count',x.cnt) order by x.quantity desc) from (select im.movement_type,sum(im.quantity_change) quantity,count(*) cnt from public.inventory_movements im where im.organization_id=p_organization_id and (p_store_id is null or im.store_id=p_store_id) and (v_from is null or im.created_at>=v_from) and (v_to is null or im.created_at<v_to) group by im.movement_type) x),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.commercial_reports_summary(uuid,uuid,date,date) from public, anon;
grant execute on function public.commercial_reports_summary(uuid,uuid,date,date) to authenticated;
