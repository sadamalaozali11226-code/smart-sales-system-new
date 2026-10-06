create or replace function private.transfer_stock(
  p_organization_id uuid,
  p_from_store_id uuid,
  p_to_store_id uuid,
  p_product_id bigint,
  p_quantity integer,
  p_notes text default null
)
returns public.stock_transfers
language plpgsql
security definer
set search_path = public, private
as $function$
declare
  v_from public.store_products%rowtype;
  v_to public.store_products%rowtype;
  v_transfer public.stock_transfers;
  v_destination_cost numeric;
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

  v_destination_cost :=
    case
      when v_to.quantity <= 0 then v_from.average_cost
      else ((v_to.quantity * v_to.average_cost) + (p_quantity * v_from.average_cost))
           / (v_to.quantity + p_quantity)
    end;

  update public.store_products
     set quantity=quantity-p_quantity, updated_at=now()
   where id=v_from.id;

  update public.store_products
     set quantity=quantity+p_quantity,
         average_cost=coalesce(v_destination_cost, v_to.average_cost),
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
