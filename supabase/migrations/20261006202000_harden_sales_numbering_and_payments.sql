-- Commercial V1: sales document numbering and payment hardening
-- Applied to the production Supabase project before this migration file was committed.

create table if not exists private.document_sequences (
  organization_id uuid not null,
  document_type text not null,
  next_number bigint not null default 1,
  updated_at timestamptz not null default now(),
  primary key (organization_id, document_type),
  check (next_number > 0)
);

create or replace function private.next_document_number(
  p_organization_id uuid,
  p_document_type text,
  p_prefix text default 'DOC'
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_number bigint;
begin
  if p_organization_id is null then
    raise exception 'organization is required';
  end if;
  if nullif(trim(p_document_type), '') is null then
    raise exception 'document type is required';
  end if;
  if nullif(trim(p_prefix), '') is null then
    raise exception 'document prefix is required';
  end if;

  insert into private.document_sequences(
    organization_id, document_type, next_number, updated_at
  )
  values (
    p_organization_id, trim(p_document_type), 2, now()
  )
  on conflict (organization_id, document_type)
  do update set
    next_number = private.document_sequences.next_number + 1,
    updated_at = now()
  returning next_number - 1 into v_number;

  return upper(trim(p_prefix)) || '-' || lpad(v_number::text, 6, '0');
end;
$function$;

revoke all on function private.next_document_number(uuid, text, text) from public;

create or replace function private.create_sale_transaction(
  p_organization_id uuid,
  p_store_id uuid,
  p_invoice_number text,
  p_customer_id bigint default null,
  p_items jsonb default '[]'::jsonb,
  p_discount numeric default 0,
  p_tax numeric default 0,
  p_paid_amount numeric default 0,
  p_payment_method text default 'cash',
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

    select sp.average_cost into v_unit_cost
    from public.store_products sp
    where sp.store_id = p_store_id and sp.product_id = v_item.product_id
    for update;

    v_item_total := (v_unit_price * v_item.quantity) - v_item.discount;
    v_cost_total := v_unit_cost * v_item.quantity;

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

create or replace function private.record_sale_payment(
  p_sale_id bigint,
  p_amount numeric,
  p_payment_method text default 'cash',
  p_reference text default null
)
returns json
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sale public.sales%rowtype;
  v_payment_id bigint;
  v_paid_before numeric;
  v_paid_amount numeric;
  v_remaining numeric;
  v_payment_status text;
  v_payment_method text;
  v_reference text;
  v_audit_id bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Invalid payment amount';
  end if;

  v_payment_method := coalesce(nullif(trim(p_payment_method), ''), 'cash');
  v_reference := nullif(trim(p_reference), '');

  select * into v_sale
  from public.sales
  where id = p_sale_id
  for update;

  if not found then raise exception 'Sale not found'; end if;
  if not private.is_org_store_member(v_sale.organization_id, v_sale.store_id) then
    raise exception 'Access denied for this organization/store';
  end if;
  if not private.has_org_permission(v_sale.organization_id, 'payments.create') then
    raise exception 'Permission denied: payments.create';
  end if;
  if v_sale.status = 'cancelled' then
    raise exception 'Cannot pay a cancelled sale';
  end if;

  select coalesce(sum(amount), 0) into v_paid_before
  from public.payments where sale_id = p_sale_id;

  v_remaining := v_sale.total - v_paid_before;
  if v_remaining <= 0 then raise exception 'Invoice is already fully paid'; end if;
  if p_amount > v_remaining then
    raise exception 'Payment exceeds remaining amount. Remaining: %', v_remaining;
  end if;

  insert into public.payments(
    sale_id, amount, payment_method, reference, paid_at
  )
  values(p_sale_id, p_amount, v_payment_method, v_reference, now())
  returning id into v_payment_id;

  v_paid_amount := v_paid_before + p_amount;
  v_remaining := v_sale.total - v_paid_amount;

  if v_remaining <= 0.001 then
    v_payment_status := 'paid';
    v_remaining := 0;
  elsif v_paid_amount > 0 then
    v_payment_status := 'partial';
  else
    v_payment_status := 'unpaid';
  end if;

  update public.sales
  set payment_status = v_payment_status
  where id = p_sale_id;

  v_audit_id := private.write_audit_log(
    v_sale.organization_id,
    v_sale.store_id,
    'sale.payment_received',
    'sale',
    p_sale_id::text,
    jsonb_build_object(
      'invoice_number', v_sale.invoice_number,
      'payment_id', v_payment_id,
      'payment_amount', p_amount,
      'payment_method', v_payment_method,
      'reference', v_reference,
      'previous_paid_amount', v_paid_before,
      'paid_amount', v_paid_amount,
      'remaining_amount', v_remaining,
      'payment_status', v_payment_status
    )
  );

  return json_build_object(
    'success', true,
    'sale_id', p_sale_id,
    'invoice_number', v_sale.invoice_number,
    'total', v_sale.total,
    'previousPaidAmount', v_paid_before,
    'paymentAmount', p_amount,
    'paidAmount', v_paid_amount,
    'remainingAmount', v_remaining,
    'paymentStatus', v_payment_status,
    'paymentMethod', v_payment_method,
    'reference', v_reference,
    'paymentId', v_payment_id,
    'auditLogId', v_audit_id
  );
end;
$function$;

create or replace function public.record_sale_payment(
  p_sale_id bigint,
  p_amount numeric,
  p_payment_method text default 'cash',
  p_reference text default null
)
returns json
language plpgsql
set search_path = 'public', 'private'
as $function$
begin
  return private.record_sale_payment(
    p_sale_id, p_amount, p_payment_method, p_reference
  );
end;
$function$;

revoke execute on function public.record_sale_payment(bigint, numeric, text, text) from public;
grant execute on function public.record_sale_payment(bigint, numeric, text, text) to authenticated;
