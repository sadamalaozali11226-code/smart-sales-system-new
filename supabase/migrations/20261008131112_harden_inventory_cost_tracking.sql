-- Cost-aware inventory accounting: distinguish known costs from unknown opening-stock costs.
alter table public.store_products
  add column if not exists cost_known boolean not null default false;

update public.store_products set cost_known=false;
update public.store_products set average_cost=0 where not cost_known;
update public.sale_items set unit_cost=null,cost_total=null
where unit_cost is not null or cost_total is not null;

CREATE OR REPLACE FUNCTION private.cancel_purchase(p_organization_id uuid, p_store_id uuid, p_purchase_receipt_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_receipt public.purchase_receipts%rowtype;
  v_item record;
  v_balance public.store_products%rowtype;
  v_new_qty integer;
  v_current_value numeric;
  v_removed_value numeric;
  v_new_value numeric;
  v_new_cost numeric;
  v_new_cost_known boolean;
  v_reason text;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  if not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'organization/store access denied';
  end if;

  if not private.has_org_permission(p_organization_id, 'purchases.cancel') then
    raise exception 'purchases.cancel permission required';
  end if;

  v_reason := nullif(btrim(coalesce(p_reason, '')), '');

  if v_reason is null then
    raise exception 'cancellation reason is required';
  end if;

  select *
    into v_receipt
    from public.purchase_receipts
   where id = p_purchase_receipt_id
     and organization_id = p_organization_id
     and store_id = p_store_id
   for update;

  if not found then
    raise exception 'purchase receipt not found';
  end if;

  if v_receipt.status <> 'completed' then
    raise exception 'only completed purchase receipts can be cancelled';
  end if;

  if coalesce(v_receipt.payment_status, 'unpaid') <> 'unpaid' then
    raise exception 'paid or partially paid purchases cannot be cancelled yet; reverse supplier payment first';
  end if;

  for v_item in
    select product_id, quantity, unit_cost
      from public.purchase_receipt_items
     where receipt_id = v_receipt.id
  loop
    select *
      into v_balance
      from public.store_products
     where store_id = p_store_id
       and product_id = v_item.product_id
     for update;

    if not found then
      raise exception 'product is no longer assigned to this store';
    end if;

    if v_balance.quantity < v_item.quantity then
      raise exception 'cannot cancel purchase because current stock is below the purchased quantity for product %', v_item.product_id;
    end if;

    v_new_qty := v_balance.quantity - v_item.quantity;

    if v_balance.cost_known then
      v_current_value := v_balance.quantity * coalesce(v_balance.average_cost, 0);
      v_removed_value := v_item.quantity * v_item.unit_cost;
      v_new_value := v_current_value - v_removed_value;
      if v_new_value < 0 then raise exception 'cannot reconcile inventory value while cancelling purchase for product %', v_item.product_id; end if;
      v_new_cost := case when v_new_qty > 0 then round(v_new_value / v_new_qty, 6) else 0 end;
      v_new_cost_known := v_new_qty > 0;
    else
      v_new_cost := 0;
      v_new_cost_known := false;
    end if;

    update public.store_products
       set quantity = v_new_qty,
           average_cost = v_new_cost,
           cost_known = v_new_cost_known,
           updated_at = now()
     where id = v_balance.id;

    insert into public.inventory_movements(
      product_id,
      movement_type,
      quantity_change,
      reference_type,
      reference_id,
      notes,
      organization_id,
      store_id
    )
    values(
      v_item.product_id,
      'adjustment',
      -v_item.quantity,
      'purchase_receipt',
      v_receipt.id,
      'Purchase cancelled: ' || v_reason,
      p_organization_id,
      p_store_id
    );
  end loop;

  update public.purchase_receipts
     set status = 'cancelled',
         cancelled_at = now(),
         cancelled_by = auth.uid(),
         cancel_reason = v_reason,
         payment_status = 'unpaid'
   where id = v_receipt.id
     and organization_id = p_organization_id
     and store_id = p_store_id;

  perform private.write_audit_log(
    p_organization_id,
    p_store_id,
    'purchase.cancelled',
    'purchase_receipt',
    v_receipt.id::text,
    jsonb_build_object(
      'receipt_number', v_receipt.receipt_number,
      'reason', v_reason,
      'supplier_id', v_receipt.supplier_id,
      'total', v_receipt.total
    )
  );

  return jsonb_build_object(
    'id', v_receipt.id,
    'receipt_number', v_receipt.receipt_number,
    'status', 'cancelled',
    'reason', v_reason
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.commercial_reports(p_organization_id uuid, p_store_id uuid DEFAULT NULL::uuid, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  if p_store_id is null then
    if not exists (
      select 1
      from public.organization_members om
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
        select
          s.id,
          s.invoice_number,
          coalesce(c.name, 'نقدي') as customer_name,
          s.total,
          s.payment_status,
          s.status,
          s.created_at
        from public.sales s
        left join public.customers c on c.id = s.customer_id
        where s.organization_id = p_organization_id
          and (p_store_id is null or s.store_id = p_store_id)
          and s.status <> 'cancelled'
          and (p_from_date is null or s.created_at >= p_from_date::timestamptz)
          and (p_to_date is null or s.created_at < (p_to_date + 1)::timestamptz)
        order by s.created_at desc
        limit 200
      ) x
    ), '[]'::jsonb),

    'purchases', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select
          pr.id,
          pr.receipt_number,
          pr.supplier_invoice_number,
          coalesce(sp.name, '-') as supplier_name,
          pr.total,
          pr.payment_status,
          pr.status,
          pr.created_at
        from public.purchase_receipts pr
        left join public.suppliers sp on sp.id = pr.supplier_id
        where pr.organization_id = p_organization_id
          and (p_store_id is null or pr.store_id = p_store_id)
          and pr.status <> 'cancelled'
          and (p_from_date is null or pr.created_at >= p_from_date::timestamptz)
          and (p_to_date is null or pr.created_at < (p_to_date + 1)::timestamptz)
        order by pr.created_at desc
        limit 200
      ) x
    ), '[]'::jsonb),

    'inventory', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.quantity asc, x.product_name)
      from (
        select
          sp.product_id,
          p.name as product_name,
          sp.quantity,
          sp.reorder_level,
          sp.average_cost,
          sp.cost_known,
          case when sp.cost_known then (sp.quantity * coalesce(sp.average_cost, 0))::numeric else null end as stock_value
        from public.store_products sp
        join public.products p on p.id = sp.product_id
        where sp.store_id = p_store_id
          and p.organization_id = p_organization_id
        order by sp.quantity asc, p.name
        limit 500
      ) x
    ), '[]'::jsonb),

    'customers', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.balance desc, x.customer_name)
      from (
        select * from private.customer_account_summary(p_organization_id, p_store_id)
        where balance <> 0
        order by balance desc, customer_name
        limit 200
      ) x
    ), '[]'::jsonb),

    'suppliers', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.balance desc, x.supplier_name)
      from (
        select * from private.supplier_account_summary(p_organization_id, p_store_id)
        where balance <> 0
        order by balance desc, supplier_name
        limit 200
      ) x
    ), '[]'::jsonb),

    'expenses', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.expense_date desc, x.id desc)
      from (
        select
          e.id,
          e.expense_number,
          e.category,
          e.amount,
          e.expense_date,
          e.payment_method,
          e.status,
          e.created_at
        from public.expenses e
        where e.organization_id = p_organization_id
          and (p_store_id is null or e.store_id = p_store_id)
          and (p_from_date is null or e.expense_date >= p_from_date)
          and (p_to_date is null or e.expense_date <= p_to_date)
        order by e.expense_date desc, e.id desc
        limit 200
      ) x
    ), '[]'::jsonb),

    'movements', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select
          im.id,
          p.name as product_name,
          im.movement_type,
          im.quantity_change,
          im.reference_type,
          im.reference_id,
          im.notes,
          im.created_at
        from public.inventory_movements im
        left join public.products p on p.id = im.product_id
        where im.organization_id = p_organization_id
          and (p_store_id is null or im.store_id = p_store_id)
          and (p_from_date is null or im.created_at >= p_from_date::timestamptz)
          and (p_to_date is null or im.created_at < (p_to_date + 1)::timestamptz)
        order by im.created_at desc
        limit 300
      ) x
    ), '[]'::jsonb),

    'transfers', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select
          st.id,
          p.name as product_name,
          sf.name as from_store_name,
          stt.name as to_store_name,
          st.quantity,
          st.created_at,
          st.notes
        from public.stock_transfers st
        join public.products p on p.id = st.product_id
        join public.stores sf on sf.id = st.from_store_id
        join public.stores stt on stt.id = st.to_store_id
        where st.organization_id = p_organization_id
          and (p_store_id is null or st.from_store_id = p_store_id or st.to_store_id = p_store_id)
          and (p_from_date is null or st.created_at >= p_from_date::timestamptz)
          and (p_to_date is null or st.created_at < (p_to_date + 1)::timestamptz)
        order by st.created_at desc
        limit 200
      ) x
    ), '[]'::jsonb)
  );

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.commercial_reports_summary(p_organization_id uuid, p_store_id uuid DEFAULT NULL::uuid, p_from_date date DEFAULT NULL::date, p_to_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_from timestamptz := case when p_from_date is null then null else p_from_date::timestamptz end;
  v_to timestamptz := case when p_to_date is null then null else (p_to_date + 1)::timestamptz end;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.organization_members om
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.status = 'active'
  ) then
    raise exception 'Organization access denied';
  end if;

  if p_store_id is not null and not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'Store access denied';
  end if;

  if p_from_date is not null and p_to_date is not null and p_from_date > p_to_date then
    raise exception 'Invalid date range';
  end if;

  select jsonb_build_object(
    'period', jsonb_build_object('from', p_from_date, 'to', p_to_date),
    'sales', jsonb_build_object(
      'count', coalesce((
        select count(*) from public.sales s
        where s.organization_id=p_organization_id
          and (p_store_id is null or s.store_id=p_store_id)
          and s.status='completed'
          and (v_from is null or s.created_at >= v_from)
          and (v_to is null or s.created_at < v_to)
      ),0),
      'gross_total', coalesce((
        select sum(s.total) from public.sales s
        where s.organization_id=p_organization_id
          and (p_store_id is null or s.store_id=p_store_id)
          and s.status='completed'
          and (v_from is null or s.created_at >= v_from)
          and (v_to is null or s.created_at < v_to)
      ),0),
      'discount_total', coalesce((
        select sum(s.discount) from public.sales s
        where s.organization_id=p_organization_id
          and (p_store_id is null or s.store_id=p_store_id)
          and s.status='completed'
          and (v_from is null or s.created_at >= v_from)
          and (v_to is null or s.created_at < v_to)
      ),0),
      'tax_total', coalesce((
        select sum(s.tax) from public.sales s
        where s.organization_id=p_organization_id
          and (p_store_id is null or s.store_id=p_store_id)
          and s.status='completed'
          and (v_from is null or s.created_at >= v_from)
          and (v_to is null or s.created_at < v_to)
      ),0),
      'paid_total', coalesce((
        select sum(p.amount) from public.payments p
        join public.sales s on s.id=p.sale_id
        where s.organization_id=p_organization_id
          and (p_store_id is null or s.store_id=p_store_id)
          and s.status='completed'
          and (v_from is null or s.created_at >= v_from)
          and (v_to is null or s.created_at < v_to)
      ),0),
      'returns_total', coalesce((
        select sum(sr.amount) from public.refunds sr
        join public.sales s on s.id=sr.sale_id
        where sr.organization_id=p_organization_id
          and (p_store_id is null or sr.store_id=p_store_id)
          and s.status<>'cancelled'
          and (v_from is null or sr.refunded_at >= v_from)
          and (v_to is null or sr.refunded_at < v_to)
      ),0),
      'payment_methods', coalesce((
        select jsonb_agg(jsonb_build_object('method',x.payment_method,'amount',x.amount) order by x.amount desc)
        from (
          select coalesce(p.payment_method,'other') payment_method, sum(p.amount) amount
          from public.payments p join public.sales s on s.id=p.sale_id
          where s.organization_id=p_organization_id
            and (p_store_id is null or s.store_id=p_store_id)
            and s.status='completed'
            and (v_from is null or s.created_at >= v_from)
            and (v_to is null or s.created_at < v_to)
          group by coalesce(p.payment_method,'other')
        ) x
      ), '[]'::jsonb),
      'top_products', coalesce((
        select jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales_total',x.sales_total) order by x.sales_total desc)
        from (
          select si.product_id, max(si.product_name) product_name, sum(si.quantity) quantity, sum(si.total) sales_total
          from public.sale_items si join public.sales s on s.id=si.sale_id
          where s.organization_id=p_organization_id
            and (p_store_id is null or s.store_id=p_store_id)
            and s.status='completed'
            and (v_from is null or s.created_at >= v_from)
            and (v_to is null or s.created_at < v_to)
          group by si.product_id
          order by sum(si.total) desc
          limit 10
        ) x
      ), '[]'::jsonb)
    ),
    'purchases', jsonb_build_object(
      'count', coalesce((
        select count(*) from public.purchase_receipts pr
        where pr.organization_id=p_organization_id
          and (p_store_id is null or pr.store_id=p_store_id)
          and pr.status<>'cancelled'
          and (v_from is null or pr.created_at >= v_from)
          and (v_to is null or pr.created_at < v_to)
      ),0),
      'total', coalesce((
        select sum(pr.total) from public.purchase_receipts pr
        where pr.organization_id=p_organization_id
          and (p_store_id is null or pr.store_id=p_store_id)
          and pr.status<>'cancelled'
          and (v_from is null or pr.created_at >= v_from)
          and (v_to is null or pr.created_at < v_to)
      ),0),
      'returns_total', coalesce((
        select sum(pr.total) from public.purchase_returns pr
        where pr.organization_id=p_organization_id
          and (p_store_id is null or pr.store_id=p_store_id)
          and pr.status='completed'
          and (v_from is null or pr.created_at >= v_from)
          and (v_to is null or pr.created_at < v_to)
      ),0),
      'supplier_payments', coalesce((
        select sum(sp.amount) from public.supplier_payments sp
        where sp.organization_id=p_organization_id
          and (p_store_id is null or sp.store_id=p_store_id)
          and (v_from is null or sp.paid_at >= v_from)
          and (v_to is null or sp.paid_at < v_to)
      ),0),
      'top_suppliers', coalesce((
        select jsonb_agg(jsonb_build_object('supplier_id',x.supplier_id,'supplier_name',x.supplier_name,'total',x.total) order by x.total desc)
        from (
          select pr.supplier_id, max(su.name) supplier_name, sum(pr.total) total
          from public.purchase_receipts pr
          left join public.suppliers su on su.id=pr.supplier_id
          where pr.organization_id=p_organization_id
            and (p_store_id is null or pr.store_id=p_store_id)
            and pr.status<>'cancelled'
            and (v_from is null or pr.created_at >= v_from)
            and (v_to is null or pr.created_at < v_to)
          group by pr.supplier_id
          order by sum(pr.total) desc
          limit 10
        ) x
      ), '[]'::jsonb)
    ),
    'inventory', jsonb_build_object(
      'product_count', coalesce((
        select count(*) from public.store_products sp
        where sp.store_id=coalesce(p_store_id,sp.store_id)
          and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)
      ),0),
      'quantity_total', coalesce((
        select sum(sp.quantity) from public.store_products sp
        where (p_store_id is null or sp.store_id=p_store_id)
          and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)
      ),0),
      'estimated_value', coalesce((
        select sum(case when sp.cost_known then sp.quantity*coalesce(sp.average_cost,0) else 0 end) from public.store_products sp
        where (p_store_id is null or sp.store_id=p_store_id)
          and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)
      ),0),
      'low_stock_count', coalesce((
        select count(*) from public.store_products sp
        where (p_store_id is null or sp.store_id=p_store_id)
          and sp.quantity <= sp.reorder_level
          and exists(select 1 from public.products p where p.id=sp.product_id and p.organization_id=p_organization_id)
      ),0),
      'items', coalesce((
        select jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'reorder_level',x.reorder_level,'average_cost',x.average_cost,'cost_known',x.cost_known,'estimated_value',x.estimated_value) order by x.quantity asc,x.product_name)
        from (
          select sp.product_id,max(p.name) product_name,sp.quantity,sp.reorder_level,coalesce(sp.average_cost,0) average_cost,sp.cost_known,case when sp.cost_known then sp.quantity*coalesce(sp.average_cost,0) else 0 end estimated_value
          from public.store_products sp join public.products p on p.id=sp.product_id
          where (p_store_id is null or sp.store_id=p_store_id) and p.organization_id=p_organization_id
          group by sp.product_id,sp.quantity,sp.reorder_level,sp.average_cost
        ) x
      ), '[]'::jsonb)
    ),
    'customers', coalesce((
      select jsonb_agg(jsonb_build_object('customer_id',x.customer_id,'customer_name',x.customer_name,'sales_total',x.sales_total,'payments',x.payments,'refunds',x.refunds,'balance',x.balance) order by x.balance desc)
      from (
        select c.id customer_id,c.name customer_name,
          coalesce((select sum(s.total) from public.sales s where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id) and (v_from is null or s.created_at>=v_from) and (v_to is null or s.created_at<v_to)),0) sales_total,
          coalesce((select sum(pay.amount) from public.payments pay join public.sales s on s.id=pay.sale_id where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id) and (v_from is null or pay.paid_at>=v_from) and (v_to is null or pay.paid_at<v_to)),0)
          + coalesce((select sum(cp.amount) from public.customer_payments cp where cp.customer_id=c.id and cp.organization_id=p_organization_id and (p_store_id is null or cp.store_id=p_store_id) and (v_from is null or cp.paid_at>=v_from) and (v_to is null or cp.paid_at<v_to)),0) payments,
          coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where s.customer_id=c.id and r.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id) and (v_from is null or r.refunded_at>=v_from) and (v_to is null or r.refunded_at<v_to)),0) refunds,
          coalesce((select sum(s.total) from public.sales s where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0)
          - coalesce((select sum(pay.amount) from public.payments pay join public.sales s on s.id=pay.sale_id where s.customer_id=c.id and s.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or s.store_id=p_store_id)),0)
          - coalesce((select sum(cp.amount) from public.customer_payments cp where cp.customer_id=c.id and cp.organization_id=p_organization_id and (p_store_id is null or cp.store_id=p_store_id)),0)
          - coalesce((select sum(r.amount) from public.refunds r join public.sales s on s.id=r.sale_id where s.customer_id=c.id and r.organization_id=p_organization_id and s.status<>'cancelled' and (p_store_id is null or r.store_id=p_store_id)),0) balance
        from public.customers c where c.organization_id=p_organization_id
      ) x
    ), '[]'::jsonb),
    'suppliers', coalesce((
      select jsonb_agg(jsonb_build_object('supplier_id',x.supplier_id,'supplier_name',x.supplier_name,'purchases_total',x.purchases_total,'payments',x.payments,'returns',x.returns,'refunds',x.refunds,'balance',x.balance) order by x.balance desc)
      from (
        select su.id supplier_id,su.name supplier_name,
          coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id)),0) purchases_total,
          coalesce((select sum(sp.amount) from public.supplier_payments sp where sp.supplier_id=su.id and sp.organization_id=p_organization_id and (p_store_id is null or sp.store_id=p_store_id)),0) payments,
          coalesce((select sum(pr.total) from public.purchase_returns pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status='completed' and (p_store_id is null or pr.store_id=p_store_id)),0) returns,
          coalesce((select sum(sr.amount) from public.supplier_refunds sr where sr.supplier_id=su.id and sr.organization_id=p_organization_id and (p_store_id is null or sr.store_id=p_store_id)),0) refunds,
          coalesce((select sum(pr.total) from public.purchase_receipts pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status<>'cancelled' and (p_store_id is null or pr.store_id=p_store_id)),0)
          - coalesce((select sum(sp.amount) from public.supplier_payments sp where sp.supplier_id=su.id and sp.organization_id=p_organization_id and (p_store_id is null or sp.store_id=p_store_id)),0)
          - coalesce((select sum(pr.total) from public.purchase_returns pr where pr.supplier_id=su.id and pr.organization_id=p_organization_id and pr.status='completed' and (p_store_id is null or pr.store_id=p_store_id)),0)
          + coalesce((select sum(sr.amount) from public.supplier_refunds sr where sr.supplier_id=su.id and sr.organization_id=p_organization_id and (p_store_id is null or sr.store_id=p_store_id)),0) balance
        from public.suppliers su where su.organization_id=p_organization_id
      ) x
    ), '[]'::jsonb),
    'expenses', jsonb_build_object(
      'total', coalesce((select sum(e.amount) from public.expenses e where e.organization_id=p_organization_id and (p_store_id is null or e.store_id=p_store_id) and e.status='completed' and (v_from is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date)),0),
      'count', coalesce((select count(*) from public.expenses e where e.organization_id=p_organization_id and (p_store_id is null or e.store_id=p_store_id) and e.status='completed' and (v_from is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date)),0),
      'by_category', coalesce((select jsonb_agg(jsonb_build_object('category',x.category,'amount',x.amount) order by x.amount desc) from (select e.category,sum(e.amount) amount from public.expenses e where e.organization_id=p_organization_id and (p_store_id is null or e.store_id=p_store_id) and e.status='completed' and (v_from is null or e.expense_date>=p_from_date) and (p_to_date is null or e.expense_date<=p_to_date) group by e.category order by sum(e.amount) desc) x),'[]'::jsonb)
    ),
    'inventory_movements', coalesce((
      select jsonb_agg(jsonb_build_object('movement_type',x.movement_type,'quantity',x.quantity,'count',x.cnt) order by x.quantity desc)
      from (select im.movement_type,sum(im.quantity_change) quantity,count(*) cnt from public.inventory_movements im where im.organization_id=p_organization_id and (p_store_id is null or im.store_id=p_store_id) and (v_from is null or im.created_at>=v_from) and (v_to is null or im.created_at<v_to) group by im.movement_type) x
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.create_product_for_store_with_cost(p_organization_id uuid, p_store_id uuid, p_name text, p_price numeric, p_initial_quantity integer DEFAULT 0, p_reorder_level integer DEFAULT 0, p_notes text DEFAULT NULL::text, p_initial_unit_cost numeric DEFAULT NULL::numeric)
 RETURNS store_products
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare v_product public.products; v_store_product public.store_products;
begin
if auth.uid() is null then raise exception 'authentication required'; end if;
if not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'organization/store access denied'; end if;
if not private.has_org_permission(p_organization_id,'products.create') then raise exception 'products.create permission required'; end if;
if not private.has_org_permission(p_organization_id,'inventory.adjust') then raise exception 'inventory.adjust permission required'; end if;
if p_initial_quantity < 0 or p_reorder_level < 0 then raise exception 'initial quantity and reorder level must be nonnegative'; end if;
if p_initial_unit_cost is not null and p_initial_unit_cost < 0 then raise exception 'initial unit cost must be nonnegative'; end if;
v_product:=private.create_product(p_organization_id,p_name,p_price,0);
insert into public.store_products(store_id,product_id,quantity,reorder_level,average_cost,cost_known)
values(p_store_id,v_product.id,p_initial_quantity,p_reorder_level,case when p_initial_quantity>0 and p_initial_unit_cost is not null then p_initial_unit_cost else 0 end,case when p_initial_quantity>0 and p_initial_unit_cost is not null then true else false end)
returning * into v_store_product;
if p_initial_quantity>0 then
insert into public.inventory_movements(product_id,movement_type,quantity_change,reference_type,reference_id,notes,organization_id,store_id)
values(v_product.id,'opening',p_initial_quantity,'store_product',v_store_product.id,coalesce(p_notes,'Initial store stock'),p_organization_id,p_store_id);
end if;
perform private.write_audit_log(p_organization_id,p_store_id,'inventory.product_added_to_store','store_product',v_store_product.id::text,jsonb_build_object('product_id',v_product.id,'initial_quantity',p_initial_quantity,'initial_unit_cost',p_initial_unit_cost,'reorder_level',p_reorder_level));
return v_store_product;
end;$function$;

CREATE OR REPLACE FUNCTION private.create_purchase(p_organization_id uuid, p_store_id uuid, p_supplier_id bigint, p_receipt_number text, p_items jsonb, p_discount numeric DEFAULT 0, p_tax numeric DEFAULT 0, p_paid_amount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_reference text DEFAULT NULL::text, p_due_date date DEFAULT NULL::date, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_receipt public.purchase_receipts;
  v_supplier public.suppliers;
  v_item jsonb;
  v_product_id bigint;
  v_quantity integer;
  v_unit_cost numeric;
  v_subtotal numeric := 0;
  v_discount numeric := coalesce(p_discount,0);
  v_tax numeric := coalesce(p_tax,0);
  v_total numeric;
  v_paid numeric := coalesce(p_paid_amount,0);
  v_payment_id bigint;
  v_balance public.store_products%rowtype;
  v_old_qty integer;
  v_old_cost numeric;
  v_old_cost_known boolean;
  v_new_cost numeric;
  v_payment_status text;
  v_item_count integer;
  v_internal_receipt_number text;
  v_supplier_invoice_number text := nullif(btrim(coalesce(p_receipt_number,'')),'');
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'organization/store access denied'; end if;
  if not private.has_org_permission(p_organization_id,'purchases.create') then raise exception 'purchases.create permission required'; end if;
  if v_supplier_invoice_number is null then raise exception 'supplier invoice number is required'; end if;
  if p_supplier_id is null then raise exception 'supplier is required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'purchase items are required'; end if;
  if v_discount < 0 or v_tax < 0 or v_paid < 0 then raise exception 'discount, tax and payment must be nonnegative'; end if;

  if exists (
    select 1 from jsonb_array_elements(p_items) x
    group by (x->>'product_id') having count(*) > 1
  ) then raise exception 'duplicate product lines are not allowed'; end if;

  select * into v_supplier
  from public.suppliers
  where id=p_supplier_id and organization_id=p_organization_id
  for update;
  if not found then raise exception 'supplier not found'; end if;
  if v_supplier.status <> 'active' then raise exception 'supplier is inactive'; end if;

  if exists (
    select 1
    from public.purchase_receipts pr
    where pr.organization_id = p_organization_id
      and pr.supplier_id = p_supplier_id
      and pr.supplier_invoice_number is not null
      and lower(btrim(pr.supplier_invoice_number)) = lower(v_supplier_invoice_number)
  ) then
    raise exception 'supplier invoice number already exists for this supplier';
  end if;

  v_item_count := jsonb_array_length(p_items);

  for v_item in select value from jsonb_array_elements(p_items) loop
    if (v_item->>'product_id') is null or (v_item->>'quantity') is null or (v_item->>'unit_cost') is null
      then raise exception 'invalid purchase item'; end if;

    v_product_id := (v_item->>'product_id')::bigint;
    v_quantity := (v_item->>'quantity')::integer;
    v_unit_cost := (v_item->>'unit_cost')::numeric;

    if v_quantity <= 0 or v_unit_cost < 0 then raise exception 'invalid purchase item values'; end if;

    if not exists (
      select 1 from public.products
      where id=v_product_id and organization_id=p_organization_id
    ) then raise exception 'product not found in organization'; end if;

    select * into v_balance
    from public.store_products
    where store_id=p_store_id and product_id=v_product_id
    for update;
    if not found then raise exception 'product is not assigned to this store'; end if;

    v_subtotal := v_subtotal + (v_quantity * v_unit_cost);
  end loop;

  if v_discount > v_subtotal then raise exception 'discount cannot exceed subtotal'; end if;
  v_total := v_subtotal - v_discount + v_tax;
  if v_paid > v_total then raise exception 'payment cannot exceed purchase total'; end if;

  v_payment_status :=
    case when v_paid = 0 then 'unpaid'
         when v_paid = v_total then 'paid'
         else 'partial' end;

  v_internal_receipt_number :=
    'PUR-' || lpad(nextval('public.purchase_receipt_number_seq')::text, 6, '0');

  insert into public.purchase_receipts(
    organization_id,store_id,receipt_number,supplier_invoice_number,notes,supplier_id,subtotal,discount,tax,total,
    payment_status,due_date,status
  )
  values(
    p_organization_id,p_store_id,v_internal_receipt_number,v_supplier_invoice_number,
    nullif(btrim(coalesce(p_notes,'')),''),p_supplier_id,v_subtotal,v_discount,v_tax,v_total,
    v_payment_status,p_due_date,'completed'
  )
  returning * into v_receipt;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::bigint;
    v_quantity := (v_item->>'quantity')::integer;
    v_unit_cost := (v_item->>'unit_cost')::numeric;

    select * into v_balance
    from public.store_products
    where store_id=p_store_id and product_id=v_product_id
    for update;

    v_old_qty := v_balance.quantity;
    v_old_cost := v_balance.average_cost;
    v_old_cost_known := v_balance.cost_known;
    v_new_cost := case
      when v_old_qty = 0 then v_unit_cost
      when v_old_cost_known then ((v_old_qty * v_old_cost) + (v_quantity * v_unit_cost)) / (v_old_qty + v_quantity)
      else 0
    end;

    update public.store_products
       set quantity=quantity+v_quantity,
           average_cost=v_new_cost,
           cost_known=(v_old_qty = 0 or v_old_cost_known),
           updated_at=now()
     where id=v_balance.id;

    insert into public.purchase_receipt_items(receipt_id,product_id,quantity,unit_cost)
    values(v_receipt.id,v_product_id,v_quantity,v_unit_cost);

    insert into public.inventory_movements(
      product_id,movement_type,quantity_change,reference_type,reference_id,notes,organization_id,store_id
    )
    values(
      v_product_id,'purchase',v_quantity,'purchase_receipt',v_receipt.id,
      'Stock received from purchase',p_organization_id,p_store_id
    );
  end loop;

  if v_paid > 0 then
    insert into public.supplier_payments(
      organization_id,store_id,supplier_id,amount,payment_method,reference,notes
    )
    values(
      p_organization_id,p_store_id,p_supplier_id,v_paid,
      coalesce(nullif(btrim(p_payment_method),''),'cash'),
      nullif(btrim(coalesce(p_reference,'')),''), 
      'Initial payment for purchase '||v_receipt.receipt_number
    )
    returning id into v_payment_id;

    insert into public.supplier_payment_allocations(
      organization_id,supplier_payment_id,purchase_receipt_id,amount
    )
    values(p_organization_id,v_payment_id,v_receipt.id,v_paid);
  end if;

  perform private.write_audit_log(
    p_organization_id,p_store_id,'purchase.created','purchase_receipt',v_receipt.id::text,
    jsonb_build_object(
      'receipt_number',v_receipt.receipt_number,
      'supplier_invoice_number',v_receipt.supplier_invoice_number,
      'supplier_id',p_supplier_id,
      'subtotal',v_subtotal,'discount',v_discount,'tax',v_tax,'total',v_total,
      'paid_amount',v_paid,'items_count',v_item_count
    )
  );

  return jsonb_build_object(
    'id',v_receipt.id,
    'receipt_number',v_receipt.receipt_number,
    'supplier_invoice_number',v_receipt.supplier_invoice_number,
    'subtotal',v_subtotal,
    'discount',v_discount,
    'tax',v_tax,
    'total',v_total,
    'paid_amount',v_paid,
    'remaining',v_total-v_paid,
    'payment_status',v_payment_status
  );
exception
  when unique_violation then
    raise exception 'supplier invoice number already exists for this supplier';
end;
$function$;

CREATE OR REPLACE FUNCTION private.create_sale_transaction(p_organization_id uuid, p_store_id uuid, p_invoice_number text, p_customer_id bigint DEFAULT NULL::bigint, p_items jsonb DEFAULT '[]'::jsonb, p_discount numeric DEFAULT 0, p_tax numeric DEFAULT 0, p_paid_amount numeric DEFAULT 0, p_payment_method text DEFAULT 'cash'::text, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_sale_id bigint;
  v_subtotal numeric := 0;
  v_total numeric := 0;
  v_payment_status text;
  v_item record;
  v_product_name text;
  v_unit_price numeric;
  v_unit_cost numeric;
  v_stock integer;
  v_item_total numeric;
  v_cost_total numeric;
  v_cost_known boolean;
  v_audit_id bigint;
  v_invoice_number text;
begin
  if v_user_id is null then raise exception 'authentication required'; end if;
  if p_organization_id is null or p_store_id is null then
    raise exception 'organization and store are required';
  end if;
  if not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'not authorized for this store';
  end if;
  if not private.has_org_permission(p_organization_id, 'sales.create') then
    raise exception 'sales.create permission required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'at least one sale item is required';
  end if;
  if p_discount < 0 or p_tax < 0 or p_paid_amount < 0 then
    raise exception 'discount, tax, and paid amount cannot be negative';
  end if;
  if nullif(trim(coalesce(p_payment_method, '')), '') is null then
    raise exception 'payment method is required';
  end if;
  if p_customer_id is not null and not exists (
    select 1 from public.customers c
    where c.id = p_customer_id and c.organization_id = p_organization_id
  ) then raise exception 'customer does not belong to organization'; end if;

  if exists (
    select 1 from jsonb_array_elements(p_items) x
    group by (x->>'product_id') having count(*) > 1
  ) then raise exception 'duplicate product in sale items'; end if;

  if exists (
    select 1 from jsonb_array_elements(p_items) x
    where nullif(x->>'product_id','') is null
       or nullif(x->>'quantity','') is null
       or (x->>'quantity')::integer <= 0
       or (x->>'product_id')::bigint <= 0
       or coalesce((x->>'discount')::numeric, 0) < 0
  ) then raise exception 'invalid sale item'; end if;

  perform 1
  from public.products p
  where p.organization_id = p_organization_id
    and p.id in (select (x->>'product_id')::bigint from jsonb_array_elements(p_items) x)
  order by p.id for update;

  if exists (
    select 1
    from jsonb_array_elements(p_items) x
    left join public.products p
      on p.id = (x->>'product_id')::bigint and p.organization_id = p_organization_id
    where p.id is null
  ) then raise exception 'one or more products do not belong to organization'; end if;

  for v_item in
    select (x->>'product_id')::bigint product_id,
           (x->>'quantity')::integer quantity,
           coalesce((x->>'discount')::numeric, 0) discount
    from jsonb_array_elements(p_items) x
    order by (x->>'product_id')::bigint
  loop
    select p.name, p.price into v_product_name, v_unit_price
    from public.products p
    where p.id = v_item.product_id and p.organization_id = p_organization_id;

    select sp.quantity, sp.average_cost into v_stock, v_unit_cost
    from public.store_products sp
    where sp.store_id = p_store_id and sp.product_id = v_item.product_id
    for update;

    if not found then raise exception 'product is not assigned to this store'; end if;
    if v_stock < v_item.quantity then
      raise exception 'insufficient stock for product % in this store', v_item.product_id;
    end if;
    if v_item.discount > (v_unit_price * v_item.quantity) then
      raise exception 'item discount exceeds item value for product %', v_item.product_id;
    end if;

    v_item_total := (v_unit_price * v_item.quantity) - v_item.discount;
    v_subtotal := v_subtotal + v_item_total;
  end loop;

  if p_discount > v_subtotal then raise exception 'sale discount exceeds subtotal'; end if;
  v_total := v_subtotal - p_discount + p_tax;
  if p_paid_amount > v_total then raise exception 'paid amount cannot exceed sale total'; end if;

  if p_paid_amount = v_total then v_payment_status := 'paid';
  elsif p_paid_amount > 0 then v_payment_status := 'partial';
  else v_payment_status := 'unpaid'; end if;

  v_invoice_number := private.next_document_number(p_organization_id, 'sale', 'INV');

  insert into public.sales(
    invoice_number, customer_id, subtotal, discount, tax, total,
    payment_status, status, notes, organization_id, store_id
  )
  values (
    v_invoice_number, p_customer_id, v_subtotal, p_discount, p_tax, v_total,
    v_payment_status, 'completed', p_notes, p_organization_id, p_store_id
  )
  returning id into v_sale_id;

  for v_item in
    select (x->>'product_id')::bigint product_id,
           (x->>'quantity')::integer quantity,
           coalesce((x->>'discount')::numeric, 0) discount
    from jsonb_array_elements(p_items) x
    order by (x->>'product_id')::bigint
  loop
    select p.name, p.price into v_product_name, v_unit_price
    from public.products p
    where p.id = v_item.product_id and p.organization_id = p_organization_id;

    select sp.average_cost, sp.cost_known into v_unit_cost, v_cost_known
    from public.store_products sp
    where sp.store_id = p_store_id and sp.product_id = v_item.product_id
    for update;

    v_item_total := (v_unit_price * v_item.quantity) - v_item.discount;
    v_cost_total := case when v_cost_known then v_unit_cost * v_item.quantity else null end;

    insert into public.sale_items(
      sale_id, product_id, product_name, unit_price, quantity, discount, total,
      unit_cost, cost_total
    )
    values (
      v_sale_id, v_item.product_id, v_product_name, v_unit_price,
      v_item.quantity, v_item.discount, v_item_total,
      v_unit_cost, v_cost_total
    );

    update public.store_products
    set quantity = quantity - v_item.quantity, updated_at = now()
    where store_id = p_store_id and product_id = v_item.product_id;

    insert into public.inventory_movements(
      product_id, movement_type, quantity_change, reference_type,
      reference_id, notes, organization_id, store_id
    )
    values (
      v_item.product_id, 'sale', -v_item.quantity, 'sale',
      v_sale_id, null, p_organization_id, p_store_id
    );
  end loop;

  if p_paid_amount > 0 then
    insert into public.payments(sale_id, amount, payment_method, reference)
    values(v_sale_id, p_paid_amount, trim(p_payment_method), p_reference);
  end if;

  v_audit_id := private.write_audit_log(
    p_organization_id, p_store_id, 'sale.created', 'sale', v_sale_id::text,
    jsonb_build_object(
      'invoice_number', v_invoice_number,
      'subtotal', v_subtotal,
      'discount', p_discount,
      'tax', p_tax,
      'total', v_total,
      'paid_amount', p_paid_amount,
      'payment_status', v_payment_status,
      'item_count', jsonb_array_length(p_items)
    )
  );

  return jsonb_build_object(
    'sale_id', v_sale_id,
    'invoice_number', v_invoice_number,
    'subtotal', v_subtotal,
    'discount', p_discount,
    'tax', p_tax,
    'total', v_total,
    'paid_amount', p_paid_amount,
    'payment_status', v_payment_status,
    'audit_log_id', v_audit_id
  );
exception
  when unique_violation then raise exception 'invoice number already exists';
end;
$function$;

CREATE OR REPLACE FUNCTION private.receive_purchase(p_organization_id uuid, p_store_id uuid, p_receipt_number text, p_items jsonb, p_notes text DEFAULT NULL::text)
 RETURNS purchase_receipts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_receipt public.purchase_receipts;
  v_item jsonb;
  v_product_id bigint;
  v_quantity integer;
  v_unit_cost numeric;
  v_balance public.store_products%rowtype;
  v_old_qty integer;
  v_old_cost numeric;
  v_new_cost numeric;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not private.is_org_store_member(p_organization_id, p_store_id) then
    raise exception 'organization/store access denied';
  end if;
  if not private.has_org_permission(p_organization_id, 'inventory.adjust') then
    raise exception 'inventory.adjust permission required';
  end if;
  if nullif(btrim(coalesce(p_receipt_number, '')), '') is null then
    raise exception 'receipt number is required';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'purchase items are required';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_items) x
    group by (x->>'product_id') having count(*) > 1
  ) then
    raise exception 'duplicate product lines are not allowed';
  end if;

  insert into public.purchase_receipts(organization_id, store_id, receipt_number, notes)
  values (p_organization_id, p_store_id, btrim(p_receipt_number),
          nullif(btrim(coalesce(p_notes, '')), ''))
  returning * into v_receipt;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::bigint;
    v_quantity := (v_item->>'quantity')::integer;
    v_unit_cost := coalesce((v_item->>'unit_cost')::numeric, 0);

    if v_product_id is null or v_quantity is null or v_quantity <= 0 then
      raise exception 'invalid purchase item';
    end if;
    if v_unit_cost < 0 then raise exception 'unit cost must be nonnegative'; end if;

    if not exists (
      select 1 from public.products
      where id = v_product_id and organization_id = p_organization_id
    ) then
      raise exception 'product not found in organization';
    end if;

    select * into v_balance
    from public.store_products
    where store_id = p_store_id and product_id = v_product_id
    for update;

    if not found then raise exception 'product is not assigned to this store'; end if;

    v_old_qty := v_balance.quantity;
    v_old_cost := v_balance.average_cost;

    if v_old_qty = 0 then
      v_new_cost := v_unit_cost;
    elsif v_balance.cost_known then
      v_new_cost := ((v_old_qty * v_old_cost) + (v_quantity * v_unit_cost))/(v_old_qty + v_quantity);
    else
      v_new_cost := 0;
    end if;

    update public.store_products
       set quantity = quantity + v_quantity,
           average_cost = v_new_cost,
           cost_known = (v_old_qty = 0 or v_balance.cost_known),
           updated_at = now()
     where id = v_balance.id;

    insert into public.purchase_receipt_items(receipt_id, product_id, quantity, unit_cost)
    values (v_receipt.id, v_product_id, v_quantity, v_unit_cost);

    insert into public.inventory_movements(
      product_id, movement_type, quantity_change, reference_type,
      reference_id, notes, organization_id, store_id
    )
    values (
      v_product_id, 'purchase', v_quantity, 'purchase_receipt',
      v_receipt.id, 'Stock received from purchase', p_organization_id, p_store_id
    );
  end loop;

  perform private.write_audit_log(
    p_organization_id, p_store_id, 'inventory.purchase_received',
    'purchase_receipt', v_receipt.id::text,
    jsonb_build_object(
      'receipt_number', v_receipt.receipt_number,
      'items_count', jsonb_array_length(p_items)
    )
  );

  return v_receipt;
exception
  when unique_violation then
    raise exception 'receipt number already exists in this store';
end;
$function$;

CREATE OR REPLACE FUNCTION private.return_purchase_items(p_organization_id uuid, p_store_id uuid, p_purchase_receipt_id bigint, p_items jsonb, p_reason text, p_refund_amount numeric DEFAULT 0, p_refund_payment_method text DEFAULT 'cash'::text, p_refund_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_purchase public.purchase_receipts%rowtype;
  v_item jsonb;
  v_ri public.purchase_receipt_items%rowtype;
  v_return public.purchase_returns%rowtype;
  v_product public.store_products%rowtype;
  v_qty integer;
  v_total numeric := 0;
  v_refund numeric := coalesce(p_refund_amount,0);
  v_return_number text;
  v_refund_id bigint;
  v_returned_before integer;
  v_available integer;
  v_item_total numeric;
  v_new_cost numeric;
  v_new_cost_known boolean;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'organization/store access denied'; end if;
  if not private.has_org_permission(p_organization_id,'inventory.adjust') then raise exception 'inventory.adjust permission required'; end if;
  if v_refund > 0 and not private.has_org_permission(p_organization_id,'supplier_payments.create') then
    raise exception 'supplier_payments.create permission required';
  end if;
  if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'return reason is required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'return items are required'; end if;
  if v_refund < 0 then raise exception 'refund amount must be nonnegative'; end if;

  select * into v_purchase
  from public.purchase_receipts
  where id=p_purchase_receipt_id and organization_id=p_organization_id and store_id=p_store_id
  for update;
  if not found then raise exception 'purchase receipt not found'; end if;
  if v_purchase.status <> 'completed' then raise exception 'only completed purchases can be returned'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if (v_item->>'purchase_receipt_item_id') is null or (v_item->>'quantity') is null then
      raise exception 'invalid purchase return item';
    end if;
    select * into v_ri from public.purchase_receipt_items
    where id=(v_item->>'purchase_receipt_item_id')::bigint
      and receipt_id=v_purchase.id
    for update;
    if not found then raise exception 'purchase receipt item not found'; end if;

    v_qty := (v_item->>'quantity')::integer;
    if v_qty <= 0 then raise exception 'return quantity must be positive'; end if;

    select coalesce(sum(pri.quantity),0)::integer into v_returned_before
    from public.purchase_return_items pri
    join public.purchase_returns pr on pr.id=pri.purchase_return_id
    where pri.purchase_receipt_item_id=v_ri.id and pr.status='completed';
    v_available := v_ri.quantity-v_returned_before;
    if v_qty > v_available then raise exception 'return quantity exceeds remaining purchased quantity'; end if;

    select * into v_product from public.store_products
    where store_id=p_store_id and product_id=v_ri.product_id
    for update;
    if not found then raise exception 'product is not assigned to this store'; end if;
    if v_product.quantity < v_qty then raise exception 'return quantity exceeds current stock'; end if;

    v_item_total := v_qty*v_ri.unit_cost;
    v_total := v_total+v_item_total;
  end loop;

  if v_refund > v_total then raise exception 'refund amount cannot exceed returned purchase value'; end if;

  v_return_number := private.next_purchase_return_number(p_organization_id);
  insert into public.purchase_returns(
    organization_id,store_id,purchase_receipt_id,supplier_id,return_number,total,refund_amount,
    refund_payment_method,refund_reference,reason,notes,created_by
  ) values (
    p_organization_id,p_store_id,v_purchase.id,v_purchase.supplier_id,v_return_number,v_total,v_refund,
    case when v_refund>0 then nullif(btrim(coalesce(p_refund_payment_method,'')),'') else null end,
    nullif(btrim(coalesce(p_refund_reference,'')),''),
    btrim(p_reason),nullif(btrim(coalesce(p_notes,'')),''),auth.uid()
  ) returning * into v_return;

  for v_item in select value from jsonb_array_elements(p_items) loop
    select * into v_ri from public.purchase_receipt_items
    where id=(v_item->>'purchase_receipt_item_id')::bigint and receipt_id=v_purchase.id
    for update;
    v_qty := (v_item->>'quantity')::integer;
    insert into public.purchase_return_items(purchase_return_id,purchase_receipt_item_id,product_id,quantity,unit_cost,total)
    values(v_return.id,v_ri.id,v_ri.product_id,v_qty,v_ri.unit_cost,v_qty*v_ri.unit_cost);

    if v_product.cost_known then
      if v_product.quantity - v_qty > 0 then
        v_new_cost := round(((v_product.quantity * v_product.average_cost) - (v_qty * v_ri.unit_cost))/(v_product.quantity - v_qty),6);
        if v_new_cost < 0 then raise exception 'cannot reconcile inventory value for purchase return'; end if;
        v_new_cost_known := true;
      else
        v_new_cost := 0; v_new_cost_known := false;
      end if;
    else
      v_new_cost := 0; v_new_cost_known := false;
    end if;
    update public.store_products set quantity=quantity-v_qty,average_cost=v_new_cost,cost_known=v_new_cost_known,updated_at=now()
    where store_id=p_store_id and product_id=v_ri.product_id;

    insert into public.inventory_movements(
      product_id,organization_id,store_id,movement_type,quantity_change,reference_type,reference_id,notes
    ) values(
      v_ri.product_id,p_organization_id,p_store_id,'return',-v_qty,'purchase_return',v_return.id,
      'Stock returned to supplier: '||btrim(p_reason)
    );
  end loop;

  if v_refund > 0 then
    if nullif(btrim(coalesce(p_refund_payment_method,'')),'') is null then raise exception 'refund payment method is required'; end if;
    insert into public.supplier_refunds(
      organization_id,store_id,supplier_id,purchase_return_id,amount,payment_method,reference,notes
    ) values(
      p_organization_id,p_store_id,v_purchase.supplier_id,v_return.id,v_refund,
      btrim(p_refund_payment_method),nullif(btrim(coalesce(p_refund_reference,'')),''),
      'Supplier refund for purchase return '||v_return.return_number
    ) returning id into v_refund_id;
  end if;

  perform private.write_audit_log(
    p_organization_id,p_store_id,'purchase.returned','purchase_return',v_return.id::text,
    jsonb_build_object('return_number',v_return_number,'purchase_receipt_id',v_purchase.id,
      'total',v_total,'refund_amount',v_refund,'refund_id',v_refund_id,'reason',btrim(p_reason))
  );

  return jsonb_build_object('id',v_return.id,'return_number',v_return_number,'total',v_total,
    'refund_amount',v_refund,'refund_id',v_refund_id,'status','completed');
end;
$function$;

CREATE OR REPLACE FUNCTION private.return_sale_items(p_organization_id uuid, p_store_id uuid, p_sale_id bigint, p_items jsonb, p_reason text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_refund_amount numeric DEFAULT 0, p_refund_payment_method text DEFAULT 'cash'::text, p_refund_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
 v_uid uuid:=auth.uid(); v_sale public.sales%rowtype; v_return public.sale_returns%rowtype;
 v_item jsonb; v_sale_item public.sale_items%rowtype; v_store_product public.store_products%rowtype;
 v_return_qty integer; v_refund numeric; v_total_refunded numeric:=0; v_previous_return_qty integer:=0;
 v_payment_total numeric:=0; v_refundable_payment numeric:=0; v_new_status text; v_audit_id bigint;
begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'organization/store access denied'; end if;
 if not private.has_org_permission(p_organization_id,'inventory.adjust') then raise exception 'missing permission: inventory.adjust'; end if;
 if p_refund_amount>0 and not private.has_org_permission(p_organization_id,'payments.refund') then raise exception 'missing permission: payments.refund'; end if;
 if p_sale_id is null then raise exception 'sale id is required'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'return items must be a non-empty JSON array'; end if;
 if p_refund_amount<0 then raise exception 'refund amount cannot be negative'; end if;
 select * into v_sale from public.sales where id=p_sale_id and organization_id=p_organization_id and store_id=p_store_id for update;
 if not found then raise exception 'sale not found'; end if;
 if v_sale.status not in ('completed','partially_returned') then raise exception 'only completed or partially returned sales can be returned'; end if;
 select coalesce(sum(p.amount),0) into v_payment_total from public.payments p where p.sale_id=p_sale_id;
 select coalesce(sum(r.amount),0) into v_total_refunded from public.refunds r where r.sale_id=p_sale_id;
 v_refundable_payment:=greatest(v_payment_total-v_total_refunded,0);
 if p_refund_amount>v_refundable_payment then raise exception 'refund exceeds refundable payment balance'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
   if (v_item->>'sale_item_id') is null then raise exception 'sale_item_id is required'; end if;
   v_return_qty:=(v_item->>'quantity')::integer;
   if v_return_qty is null or v_return_qty<=0 then raise exception 'return quantity must be greater than zero'; end if;
   v_refund:=coalesce((v_item->>'refund_amount')::numeric,0);
   if v_refund<0 then raise exception 'item refund amount cannot be negative'; end if;
   select * into v_sale_item from public.sale_items where id=(v_item->>'sale_item_id')::bigint and sale_id=p_sale_id for update;
   if not found then raise exception 'sale item not found'; end if;
   select coalesce(sum(sri.quantity),0) into v_previous_return_qty from public.sale_return_items sri join public.sale_returns sr on sr.id=sri.return_id where sri.sale_item_id=v_sale_item.id;
   if v_return_qty+v_previous_return_qty>v_sale_item.quantity then raise exception 'return quantity exceeds sold quantity for sale item %',v_sale_item.id; end if;
   if v_refund>(v_sale_item.unit_price*v_return_qty) then raise exception 'item refund exceeds returned item value'; end if;
 end loop;
 insert into public.sale_returns(sale_id,organization_id,store_id,reason,notes) values(p_sale_id,p_organization_id,p_store_id,p_reason,p_notes) returning * into v_return;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_return_qty:=(v_item->>'quantity')::integer; v_refund:=coalesce((v_item->>'refund_amount')::numeric,0);
   select * into v_sale_item from public.sale_items where id=(v_item->>'sale_item_id')::bigint and sale_id=p_sale_id for update;
   insert into public.sale_return_items(return_id,sale_item_id,product_id,quantity,unit_price,refund_amount) values(v_return.id,v_sale_item.id,v_sale_item.product_id,v_return_qty,v_sale_item.unit_price,v_refund);
   if v_sale_item.product_id is not null then
     select * into v_store_product from public.store_products where store_id=p_store_id and product_id=v_sale_item.product_id for update;
     if not found then raise exception 'product is not assigned to the sale store; return aborted'; end if;
     if v_store_product.quantity <= 0 and v_sale_item.unit_cost is not null then
       update public.store_products set quantity=quantity+v_return_qty,average_cost=v_sale_item.unit_cost,cost_known=true,updated_at=now() where id=v_store_product.id;
     elsif v_store_product.cost_known and v_sale_item.unit_cost is not null then
       update public.store_products set quantity=quantity+v_return_qty,average_cost=((v_store_product.quantity*v_store_product.average_cost)+(v_return_qty*v_sale_item.unit_cost))/(v_store_product.quantity+v_return_qty),cost_known=true,updated_at=now() where id=v_store_product.id;
     else
       update public.store_products set quantity=quantity+v_return_qty,average_cost=0,cost_known=false,updated_at=now() where id=v_store_product.id;
     end if;
     insert into public.inventory_movements(product_id,movement_type,quantity_change,reference_type,reference_id,notes,organization_id,store_id)
     values(v_sale_item.product_id,'return',v_return_qty,'sale_return',v_return.id,p_notes,p_organization_id,p_store_id);
   end if;
 end loop;
 if p_refund_amount>0 then
   insert into public.refunds(sale_id,organization_id,store_id,amount,payment_method,reference,reason)
   values(p_sale_id,p_organization_id,p_store_id,p_refund_amount,p_refund_payment_method,p_refund_reference,coalesce(p_reason,'Sale item return'));
 end if;
 select coalesce(sum(r.amount),0) into v_total_refunded from public.refunds r where r.sale_id=p_sale_id;
 v_new_status:=private.refresh_sale_return_status(p_sale_id);
 v_audit_id:=private.write_audit_log(p_organization_id,p_store_id,'sale.item_returned','sale',p_sale_id::text,jsonb_build_object('return_id',v_return.id,'refund_amount',p_refund_amount,'returned_items',jsonb_array_length(p_items),'new_sale_status',v_new_status));
 return jsonb_build_object('return_id',v_return.id,'sale_id',p_sale_id,'returned_items',jsonb_array_length(p_items),'refund_amount',p_refund_amount,'total_refunded_for_sale',v_total_refunded,'sale_status',v_new_status,'audit_log_id',v_audit_id);
end;$function$;

CREATE OR REPLACE FUNCTION private.transfer_stock(p_organization_id uuid, p_from_store_id uuid, p_to_store_id uuid, p_product_id bigint, p_quantity integer, p_notes text DEFAULT NULL::text)
 RETURNS stock_transfers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
declare
  v_from public.store_products%rowtype;
  v_to public.store_products%rowtype;
  v_transfer public.stock_transfers;
  v_destination_cost numeric;
  v_destination_cost_known boolean;
begin
  if auth.uid() is null then raise exception 'authentication required'; end if;
  if p_organization_id is null or p_from_store_id is null or p_to_store_id is null or p_product_id is null then
    raise exception 'organization, source store, destination store and product are required';
  end if;
  if p_from_store_id = p_to_store_id then raise exception 'source and destination stores must be different'; end if;
  if p_quantity <= 0 then raise exception 'transfer quantity must be greater than zero'; end if;
  if not private.is_org_store_member(p_organization_id,p_from_store_id)
     or not private.is_org_store_member(p_organization_id,p_to_store_id) then
    raise exception 'organization/store access denied';
  end if;
  if not private.has_org_permission(p_organization_id,'inventory.adjust') then
    raise exception 'inventory.adjust permission required';
  end if;
  if not exists (select 1 from public.products where id=p_product_id and organization_id=p_organization_id) then
    raise exception 'product not found in organization';
  end if;

  if p_from_store_id < p_to_store_id then
    select * into v_from from public.store_products
    where store_id=p_from_store_id and product_id=p_product_id for update;
    if not found then raise exception 'product is not assigned to source store'; end if;
    select * into v_to from public.store_products
    where store_id=p_to_store_id and product_id=p_product_id for update;
  else
    select * into v_to from public.store_products
    where store_id=p_to_store_id and product_id=p_product_id for update;
    select * into v_from from public.store_products
    where store_id=p_from_store_id and product_id=p_product_id for update;
    if not found then raise exception 'product is not assigned to source store'; end if;
  end if;

  if v_to.id is null then raise exception 'product is not assigned to destination store'; end if;
  if v_from.quantity < p_quantity then raise exception 'insufficient stock in source store'; end if;

  v_destination_cost_known := case when v_to.quantity <= 0 then v_from.cost_known else v_to.cost_known and v_from.cost_known end;
  v_destination_cost := case
      when not v_destination_cost_known then 0
      when v_to.quantity <= 0 then v_from.average_cost
      else ((v_to.quantity * v_to.average_cost) + (p_quantity * v_from.average_cost))/(v_to.quantity + p_quantity)
    end;

  update public.store_products
     set quantity=quantity-p_quantity, updated_at=now()
   where id=v_from.id;

  update public.store_products
     set quantity=quantity+p_quantity,
         average_cost=coalesce(v_destination_cost, 0),
         cost_known=v_destination_cost_known,
         updated_at=now()
   where id=v_to.id;

  insert into public.stock_transfers(organization_id,product_id,from_store_id,to_store_id,quantity,notes)
  values(p_organization_id,p_product_id,p_from_store_id,p_to_store_id,p_quantity,
         nullif(btrim(coalesce(p_notes,'')),''))
  returning * into v_transfer;

  insert into public.inventory_movements(
    product_id,movement_type,quantity_change,reference_type,reference_id,notes,organization_id,store_id
  )
  values
    (p_product_id,'adjustment',-p_quantity,'stock_transfer',v_transfer.id,
     'Transfer to store '||p_to_store_id::text,p_organization_id,p_from_store_id),
    (p_product_id,'adjustment',p_quantity,'stock_transfer',v_transfer.id,
     'Transfer from store '||p_from_store_id::text,p_organization_id,p_to_store_id);

  perform private.write_audit_log(
    p_organization_id,p_from_store_id,'inventory.stock_transferred','stock_transfer',
    v_transfer.id::text,
    jsonb_build_object('product_id',p_product_id,'from_store_id',p_from_store_id,
                       'to_store_id',p_to_store_id,'quantity',p_quantity,
                       'source_average_cost',v_from.average_cost,
                       'destination_average_cost',v_destination_cost)
  );
  return v_transfer;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_product_for_store_with_cost(p_organization_id uuid, p_store_id uuid, p_name text, p_price numeric, p_initial_quantity integer DEFAULT 0, p_reorder_level integer DEFAULT 0, p_notes text DEFAULT NULL::text, p_initial_unit_cost numeric DEFAULT NULL::numeric)
 RETURNS store_products
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$ select private.create_product_for_store_with_cost(p_organization_id,p_store_id,p_name,p_price,p_initial_quantity,p_reorder_level,p_notes,p_initial_unit_cost); $function$;

CREATE OR REPLACE FUNCTION public.inventory_valuation_report(p_organization_id uuid, p_store_id uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_current jsonb; v_flow jsonb; v_products jsonb;
begin
select jsonb_build_object('inventory_units',coalesce(sum(sp.quantity),0),'inventory_value',coalesce(sum(case when sp.cost_known then sp.quantity*sp.average_cost else 0 end),0),'products_with_stock',count(*) filter(where sp.quantity>0),'products_without_cost',count(*) filter(where sp.quantity>0 and not sp.cost_known))
into v_current from public.store_products sp join public.products pr on pr.id=sp.product_id where sp.store_id=p_store_id and pr.organization_id=p_organization_id;
select jsonb_build_object('purchase_units',coalesce(sum(pri.quantity),0),'purchase_value',coalesce(sum(pri.quantity*pri.unit_cost),0),'sold_units',coalesce((select sum(si.quantity) from public.sale_items si join public.sales s on s.id=si.sale_id where s.organization_id=p_organization_id and s.store_id=p_store_id and s.status in('completed','partially_returned','fully_returned') and si.unit_cost is not null and(p_from is null or s.created_at>=p_from)and(p_to is null or s.created_at<p_to)),0),'cogs',coalesce((select sum(si.cost_total) from public.sale_items si join public.sales s on s.id=si.sale_id where s.organization_id=p_organization_id and s.store_id=p_store_id and s.status in('completed','partially_returned','fully_returned') and si.unit_cost is not null and(p_from is null or s.created_at>=p_from)and(p_to is null or s.created_at<p_to)),0),'returned_units',coalesce((select sum(sri.quantity) from public.sale_return_items sri join public.sale_returns sr on sr.id=sri.return_id where sr.organization_id=p_organization_id and sr.store_id=p_store_id and(p_from is null or sr.created_at>=p_from)and(p_to is null or sr.created_at<p_to)),0),'returned_cost_value',coalesce((select sum(sri.quantity*si.unit_cost) from public.sale_return_items sri join public.sale_returns sr on sr.id=sri.return_id join public.sale_items si on si.id=sri.sale_item_id where sr.organization_id=p_organization_id and sr.store_id=p_store_id and si.unit_cost is not null and(p_from is null or sr.created_at>=p_from)and(p_to is null or sr.created_at<p_to)),0)) into v_flow from public.purchase_receipt_items pri join public.purchase_receipts prc on prc.id=pri.receipt_id where prc.organization_id=p_organization_id and prc.store_id=p_store_id and(p_from is null or prc.created_at>=p_from)and(p_to is null or prc.created_at<p_to);
select coalesce(jsonb_agg(to_jsonb(x) order by x.inventory_value desc nulls last,x.product_id),'[]'::jsonb) into v_products from(select sp.product_id,pr.name product_name,sp.quantity,sp.average_cost,sp.cost_known,case when sp.cost_known then sp.quantity*sp.average_cost else null end inventory_value from public.store_products sp join public.products pr on pr.id=sp.product_id where sp.store_id=p_store_id and pr.organization_id=p_organization_id limit 100)x;
return jsonb_build_object('period',jsonb_build_object('from',p_from,'to',p_to),'current_inventory',v_current,'period_flow',v_flow,'products',v_products);
end;$function$;

grant execute on function public.create_product_for_store_with_cost(uuid,uuid,text,numeric,integer,integer,text,numeric) to authenticated;
