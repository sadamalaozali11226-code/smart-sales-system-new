-- Commercial V1 security hardening.
-- Keep the exposed product-update endpoint SECURITY INVOKER; privileged mutation lives in private.
create or replace function private.update_product_for_store(p_product_id bigint,p_name text,p_price numeric,p_quantity integer,p_organization_id uuid,p_store_id uuid) returns jsonb language plpgsql security definer set search_path to public as $function$
declare
  v_user_id uuid:=auth.uid();
  v_member_id uuid;
  v_current_quantity integer;
  v_delta integer;
  v_product products%rowtype;
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_product_id is null or p_product_id<=0 then raise exception 'Invalid product id'; end if;
  if p_organization_id is null or p_store_id is null then raise exception 'Organization and store are required'; end if;
  if p_name is null or btrim(p_name)='' then raise exception 'Product name is required'; end if;
  if p_price is null or p_price<0 then raise exception 'Product price must be non-negative'; end if;
  if p_quantity is null or p_quantity<0 then raise exception 'Product quantity must be non-negative'; end if;
  select om.id into v_member_id from organization_members om join member_stores ms on ms.member_id=om.id where om.user_id=v_user_id and om.organization_id=p_organization_id and om.status='active' and ms.store_id=p_store_id limit 1;
  if v_member_id is null then raise exception 'Organization and store access denied'; end if;
  if not exists(select 1 from organization_members om join roles r on r.id=om.role_id join role_permissions rp on rp.role_id=r.id join permissions p on p.id=rp.permission_id where om.id=v_member_id and p.code='products.update') then raise exception 'Permission denied: products.update'; end if;
  select * into v_product from products where id=p_product_id and organization_id=p_organization_id for update;
  if not found then raise exception 'Product not found'; end if;
  select quantity into v_current_quantity from store_products where product_id=p_product_id and store_id=p_store_id for update;
  if not found then raise exception 'Product is not assigned to this store'; end if;
  v_delta:=p_quantity-v_current_quantity;
  if v_delta<>0 and not exists(select 1 from organization_members om join roles r on r.id=om.role_id join role_permissions rp on rp.role_id=r.id join permissions p on p.id=rp.permission_id where om.id=v_member_id and p.code='inventory.adjust') then raise exception 'Permission denied: inventory.adjust'; end if;
  update products set name=btrim(p_name),price=p_price where id=p_product_id and organization_id=p_organization_id;
  update store_products set quantity=p_quantity,updated_at=now() where product_id=p_product_id and store_id=p_store_id;
  if v_delta<>0 then insert into inventory_movements(product_id,movement_type,quantity_change,reference_type,reference_id,notes,created_at,organization_id,store_id) values(p_product_id,'adjustment',v_delta,'product_update',p_product_id,'Manual stock adjustment during product edit',now(),p_organization_id,p_store_id); end if;
  insert into audit_logs(organization_id,store_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_organization_id,p_store_id,v_user_id,'update','product',p_product_id::text,jsonb_build_object('old_name',v_product.name,'new_name',btrim(p_name),'old_price',v_product.price,'new_price',p_price,'old_quantity',v_current_quantity,'new_quantity',p_quantity,'quantity_delta',v_delta));
  return jsonb_build_object('id',p_product_id,'name',btrim(p_name),'price',p_price,'quantity',p_quantity);
end;
$function$;

revoke execute on function public.update_product_for_store(bigint,text,numeric,integer,uuid,uuid) from public,anon,authenticated;
create or replace function public.update_product_for_store(p_product_id bigint,p_name text,p_price numeric,p_quantity integer,p_organization_id uuid,p_store_id uuid) returns jsonb language sql security invoker set search_path to public,private as $function$
  select private.update_product_for_store(p_product_id,p_name,p_price,p_quantity,p_organization_id,p_store_id);
$function$;
revoke execute on function private.update_product_for_store(bigint,text,numeric,integer,uuid,uuid) from public,anon;
grant execute on function private.update_product_for_store(bigint,text,numeric,integer,uuid,uuid) to authenticated;
grant execute on function public.update_product_for_store(bigint,text,numeric,integer,uuid,uuid) to authenticated;

-- Internal read helpers remain callable only through their public SECURITY INVOKER wrappers.
revoke execute on function private.list_purchase_receipts(uuid,uuid) from public,anon;
grant execute on function private.list_purchase_receipts(uuid,uuid) to authenticated;
revoke execute on function private.purchase_return_details(uuid,uuid,bigint) from public,anon;
grant execute on function private.purchase_return_details(uuid,uuid,bigint) to authenticated;
