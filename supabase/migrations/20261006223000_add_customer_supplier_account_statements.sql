-- Commercial V1: customer and supplier account summaries/statements
-- Read-only financial views over existing sales, purchases, payments and returns.

create or replace function private.customer_account_summary(
  p_organization_id uuid, p_store_id uuid default null
) returns table(customer_id bigint,customer_name text,sales_total numeric,invoice_payments numeric,account_payments numeric,sales_refunds numeric,balance numeric)
language sql security definer set search_path=public,private as $$
  select c.id,c.name,
    coalesce((select sum(s.total) from public.sales s where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0),
    coalesce((select sum(p.amount) from public.payments p join public.sales s on s.id=p.sale_id where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0),
    coalesce((select sum(cp.amount) from public.customer_payments cp where cp.customer_id=c.id and cp.organization_id=p_organization_id and (p_store_id is null or cp.store_id=p_store_id)),0),
    coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where s.customer_id=c.id and r.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id)),0),
    coalesce((select sum(s.total) from public.sales s where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0)
    - coalesce((select sum(p.amount) from public.payments p join public.sales s on s.id=p.sale_id where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0)
    - coalesce((select sum(cp.amount) from public.customer_payments cp where cp.customer_id=c.id and cp.organization_id=p_organization_id and (p_store_id is null or cp.store_id=p_store_id)),0)
    - coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where s.customer_id=c.id and r.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id)),0)
  from public.customers c
  where c.organization_id=p_organization_id and auth.uid() is not null
    and ((p_store_id is null and exists(select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.status='active'))
      or (p_store_id is not null and private.is_org_store_member(p_organization_id,p_store_id)));
$$;

create or replace function private.supplier_account_summary(
  p_organization_id uuid, p_store_id uuid default null
) returns table(supplier_id bigint,supplier_name text,purchases_total numeric,supplier_payments numeric,supplier_refunds numeric,balance numeric)
language sql security definer set search_path=public,private as $$
  select s.id,s.name,
    coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.supplier_id=s.id and pr.organization_id=p_organization_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id)),0),
    coalesce((select sum(sp.amount) from public.supplier_payments sp where sp.supplier_id=s.id and sp.organization_id=p_organization_id and (p_store_id is null or sp.store_id=p_store_id)),0),
    coalesce((select sum(sr.amount) from public.supplier_refunds sr where sr.supplier_id=s.id and sr.organization_id=p_organization_id and (p_store_id is null or sr.store_id=p_store_id)),0),
    coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.supplier_id=s.id and pr.organization_id=p_organization_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id)),0)
    - coalesce((select sum(sp.amount) from public.supplier_payments sp where sp.supplier_id=s.id and sp.organization_id=p_organization_id and (p_store_id is null or sp.store_id=p_store_id)),0)
    - coalesce((select sum(sr.amount) from public.supplier_refunds sr where sr.supplier_id=s.id and sr.organization_id=p_organization_id and (p_store_id is null or sr.store_id=p_store_id)),0)
  from public.suppliers s
  where s.organization_id=p_organization_id and auth.uid() is not null
    and ((p_store_id is null and exists(select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.status='active'))
      or (p_store_id is not null and private.is_org_store_member(p_organization_id,p_store_id)));
$$;

create or replace function private.customer_statement(
  p_organization_id uuid,p_customer_id bigint,p_store_id uuid default null,p_from date default null,p_to date default null
) returns table(occurred_at timestamptz,entry_type text,reference_id bigint,reference_number text,description text,debit numeric,credit numeric,balance numeric)
language sql security definer set search_path=public,private as $$
  with entries(occurred_at,entry_type,reference_id,reference_number,description,debit,credit) as (
    select s.created_at,'sale',s.id,s.invoice_number,'فاتورة بيع',s.total,0::numeric from public.sales s where s.organization_id=p_organization_id and s.customer_id=p_customer_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id) and (p_from is null or s.created_at::date>=p_from) and (p_to is null or s.created_at::date<=p_to)
    union all select p.paid_at,'payment',p.id,s.invoice_number,'دفعة فاتورة',0::numeric,p.amount from public.payments p join public.sales s on s.id=p.sale_id where s.organization_id=p_organization_id and s.customer_id=p_customer_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id) and (p_from is null or p.paid_at::date>=p_from) and (p_to is null or p.paid_at::date<=p_to)
    union all select cp.paid_at,'account_payment',cp.id,null,'سداد على حساب العميل',0::numeric,cp.amount from public.customer_payments cp where cp.organization_id=p_organization_id and cp.customer_id=p_customer_id and (p_store_id is null or cp.store_id=p_store_id) and (p_from is null or cp.paid_at::date>=p_from) and (p_to is null or cp.paid_at::date<=p_to)
    union all select r.refunded_at,'refund',r.id,s.invoice_number,'مرتجع/استرداد مبيعات',r.amount,0::numeric from public.refunds r join public.sales s on s.id=r.sale_id where r.organization_id=p_organization_id and s.customer_id=p_customer_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id) and (p_from is null or r.refunded_at::date>=p_from) and (p_to is null or r.refunded_at::date<=p_to)
  )
  select e.occurred_at,e.entry_type,e.reference_id,e.reference_number,e.description,e.debit,e.credit,sum(e.debit-e.credit) over(order by e.occurred_at,e.entry_type,e.reference_id rows unbounded preceding)
  from entries e where auth.uid() is not null and ((p_store_id is null and exists(select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.status='active')) or (p_store_id is not null and private.is_org_store_member(p_organization_id,p_store_id)))
  order by e.occurred_at,e.entry_type,e.reference_id;
$$;

create or replace function private.supplier_statement(
  p_organization_id uuid,p_supplier_id bigint,p_store_id uuid default null,p_from date default null,p_to date default null
) returns table(occurred_at timestamptz,entry_type text,reference_id bigint,reference_number text,description text,debit numeric,credit numeric,balance numeric)
language sql security definer set search_path=public,private as $$
  with entries(occurred_at,entry_type,reference_id,reference_number,description,debit,credit) as (
    select pr.created_at,'purchase',pr.id,coalesce(pr.supplier_invoice_number,pr.receipt_number),'فاتورة شراء',pr.total,0::numeric from public.purchase_receipts pr where pr.organization_id=p_organization_id and pr.supplier_id=p_supplier_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id) and (p_from is null or pr.created_at::date>=p_from) and (p_to is null or pr.created_at::date<=p_to)
    union all select sp.paid_at,'payment',sp.id,null,'دفعة للمورد',0::numeric,sp.amount from public.supplier_payments sp where sp.organization_id=p_organization_id and sp.supplier_id=p_supplier_id and (p_store_id is null or sp.store_id=p_store_id) and (p_from is null or sp.paid_at::date>=p_from) and (p_to is null or sp.paid_at::date<=p_to)
    union all select sr.refunded_at,'refund',sr.id,pr.return_number,'استرداد من المورد',0::numeric,sr.amount from public.supplier_refunds sr join public.purchase_returns pr on pr.id=sr.purchase_return_id where sr.organization_id=p_organization_id and sr.supplier_id=p_supplier_id and pr.status='completed' and (p_store_id is null or sr.store_id=p_store_id) and (p_from is null or sr.refunded_at::date>=p_from) and (p_to is null or sr.refunded_at::date<=p_to)
    union all select pr.created_at,'purchase_return',pr.id,pr.return_number,'مرتجع مشتريات',0::numeric,pr.total from public.purchase_returns pr where pr.organization_id=p_organization_id and pr.supplier_id=p_supplier_id and pr.status='completed' and (p_store_id is null or pr.store_id=p_store_id) and (p_from is null or pr.created_at::date>=p_from) and (p_to is null or pr.created_at::date<=p_to)
  )
  select e.occurred_at,e.entry_type,e.reference_id,e.reference_number,e.description,e.debit,e.credit,sum(e.debit-e.credit) over(order by e.occurred_at,e.entry_type,e.reference_id rows unbounded preceding)
  from entries e where auth.uid() is not null and ((p_store_id is null and exists(select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.status='active')) or (p_store_id is not null and private.is_org_store_member(p_organization_id,p_store_id)))
  order by e.occurred_at,e.entry_type,e.reference_id;
$$;

create or replace function public.customer_account_summary(p_organization_id uuid,p_store_id uuid default null) returns table(customer_id bigint,customer_name text,sales_total numeric,invoice_payments numeric,account_payments numeric,sales_refunds numeric,balance numeric) language sql security invoker set search_path=public,private as $$ select * from private.customer_account_summary(p_organization_id,p_store_id); $$;
create or replace function public.supplier_account_summary(p_organization_id uuid,p_store_id uuid default null) returns table(supplier_id bigint,supplier_name text,purchases_total numeric,supplier_payments numeric,supplier_refunds numeric,balance numeric) language sql security invoker set search_path=public,private as $$ select * from private.supplier_account_summary(p_organization_id,p_store_id); $$;
create or replace function public.customer_statement(p_organization_id uuid,p_customer_id bigint,p_store_id uuid default null,p_from date default null,p_to date default null) returns table(occurred_at timestamptz,entry_type text,reference_id bigint,reference_number text,description text,debit numeric,credit numeric,balance numeric) language sql security invoker set search_path=public,private as $$ select * from private.customer_statement(p_organization_id,p_customer_id,p_store_id,p_from,p_to); $$;
create or replace function public.supplier_statement(p_organization_id uuid,p_supplier_id bigint,p_store_id uuid default null,p_from date default null,p_to date default null) returns table(occurred_at timestamptz,entry_type text,reference_id bigint,reference_number text,description text,debit numeric,credit numeric,balance numeric) language sql security invoker set search_path=public,private as $$ select * from private.supplier_statement(p_organization_id,p_supplier_id,p_store_id,p_from,p_to); $$;

revoke all on function private.customer_account_summary(uuid,uuid) from public,anon,authenticated;
revoke all on function private.supplier_account_summary(uuid,uuid) from public,anon,authenticated;
revoke all on function private.customer_statement(uuid,bigint,uuid,date,date) from public,anon,authenticated;
revoke all on function private.supplier_statement(uuid,bigint,uuid,date,date) from public,anon,authenticated;
grant execute on function public.customer_account_summary(uuid,uuid) to authenticated;
grant execute on function public.supplier_account_summary(uuid,uuid) to authenticated;
grant execute on function public.customer_statement(uuid,bigint,uuid,date,date) to authenticated;
grant execute on function public.supplier_statement(uuid,bigint,uuid,date,date) to authenticated;