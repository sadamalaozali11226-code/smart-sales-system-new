-- Enforce item-level refund allocation consistency at the database boundary.
-- This protects against old or direct RPC clients that send a nonzero header refund
-- while leaving every sale_return_items.refund_amount at zero.

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
 v_returnable_value numeric:=0; v_prior_return_value numeric:=0; v_item_return_value numeric:=0;
 v_refund_total numeric:=coalesce(p_refund_amount,0);
begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'organization/store access denied'; end if;
 if not private.has_org_permission(p_organization_id,'inventory.adjust') then raise exception 'missing permission: inventory.adjust'; end if;
 if v_refund_total>0 and not private.has_org_permission(p_organization_id,'payments.refund') then raise exception 'missing permission: payments.refund'; end if;
 if p_sale_id is null then raise exception 'sale id is required'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'return items must be a non-empty JSON array'; end if;
 if v_refund_total<0 then raise exception 'refund amount cannot be negative'; end if;
 if (
   select coalesce(sum(coalesce(nullif(item.value->>'refund_amount','')::numeric,0)),0)
   from jsonb_array_elements(p_items) as item(value)
 ) <> v_refund_total then
   raise exception 'sum of item refund allocations must equal refund amount';
 end if;

 if exists (
   select 1
   from (
     select value->>'sale_item_id' as sale_item_id
     from jsonb_array_elements(p_items)
   ) x
   group by sale_item_id
   having count(*) > 1
 ) then
   raise exception 'duplicate sale item in return request';
 end if;

 select * into v_sale from public.sales where id=p_sale_id and organization_id=p_organization_id and store_id=p_store_id for update;
 if not found then raise exception 'sale not found'; end if;
 if v_sale.status not in ('completed','partially_returned') then raise exception 'only completed or partially returned sales can be returned'; end if;
 select coalesce(sum(p.amount),0) into v_payment_total from public.payments p where p.sale_id=p_sale_id;
 select coalesce(sum(r.amount),0) into v_total_refunded from public.refunds r where r.sale_id=p_sale_id;
 v_refundable_payment:=greatest(v_payment_total-v_total_refunded,0);
 if v_refund_total>v_refundable_payment then raise exception 'refund exceeds refundable payment balance'; end if;
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
   if v_sale.subtotal > 0 then
     v_prior_return_value := round(((v_sale_item.total * v_sale.total / v_sale.subtotal) * v_previous_return_qty) / v_sale_item.quantity, 2);
     v_item_return_value := round(((v_sale_item.total * v_sale.total / v_sale.subtotal) * (v_previous_return_qty + v_return_qty)) / v_sale_item.quantity, 2) - v_prior_return_value;
   else
     v_prior_return_value := 0;
     v_item_return_value := 0;
   end if;
   v_returnable_value := v_returnable_value + v_item_return_value;
   if v_refund > v_item_return_value then raise exception 'item refund exceeds returned item value after invoice discounts and tax'; end if;
 end loop;
 if v_refund_total > v_returnable_value then raise exception 'refund exceeds the net value of returned items'; end if;
 if v_refund_total > 0 and nullif(btrim(coalesce(p_refund_payment_method,'')),'') is null then raise exception 'refund payment method is required'; end if;
 insert into public.sale_returns(sale_id,organization_id,store_id,reason,notes) values(p_sale_id,p_organization_id,p_store_id,p_reason,p_notes) returning * into v_return;
 for v_item in select value from jsonb_array_elements(p_items) loop
   v_return_qty:=(v_item->>'quantity')::integer; v_refund:=coalesce((v_item->>'refund_amount')::numeric,0);
   select * into v_sale_item from public.sale_items where id=(v_item->>'sale_item_id')::bigint and sale_id=p_sale_id for update;
   insert into public.sale_return_items(return_id,sale_item_id,product_id,quantity,unit_price,refund_amount) values(v_return.id,v_sale_item.id,v_sale_item.product_id,v_return_qty,v_sale_item.unit_price,v_refund);
   if v_sale_item.product_id is not null then
     select * into v_store_product from public.store_products where store_id=p_store_id and product_id=v_sale_item.product_id for update;
     if not found then raise exception 'product is not assigned to the sale store; return aborted'; end if;
     if v_sale_item.cost_total is not null and v_sale_item.unit_cost is not null and v_store_product.quantity <= 0 then
       update public.store_products set quantity=quantity+v_return_qty,average_cost=v_sale_item.unit_cost,cost_known=true,updated_at=now() where id=v_store_product.id;
     elsif v_sale_item.cost_total is not null and v_sale_item.unit_cost is not null and v_store_product.cost_known then
       update public.store_products set quantity=quantity+v_return_qty,average_cost=((v_store_product.quantity*v_store_product.average_cost)+(v_return_qty*v_sale_item.unit_cost))/(v_store_product.quantity+v_return_qty),cost_known=true,updated_at=now() where id=v_store_product.id;
     elsif v_sale_item.cost_total is null or v_sale_item.unit_cost is null then
       update public.store_products set quantity=quantity+v_return_qty,updated_at=now() where id=v_store_product.id;
     else
       update public.store_products set quantity=quantity+v_return_qty,average_cost=0,cost_known=false,updated_at=now() where id=v_store_product.id;
     end if;
     insert into public.inventory_movements(product_id,movement_type,quantity_change,reference_type,reference_id,notes,organization_id,store_id)
     values(v_sale_item.product_id,'return',v_return_qty,'sale_return',v_return.id,p_notes,p_organization_id,p_store_id);
   end if;
 end loop;
 if v_refund_total>0 then
   insert into public.refunds(sale_id,organization_id,store_id,amount,payment_method,reference,reason)
   values(p_sale_id,p_organization_id,p_store_id,v_refund_total,p_refund_payment_method,p_refund_reference,coalesce(p_reason,'Sale item return'));
 end if;
 select coalesce(sum(r.amount),0) into v_total_refunded from public.refunds r where r.sale_id=p_sale_id;
 v_new_status:=private.refresh_sale_return_status(p_sale_id);
 v_audit_id:=private.write_audit_log(p_organization_id,p_store_id,'sale.item_returned','sale',p_sale_id::text,jsonb_build_object('return_id',v_return.id,'refund_amount',v_refund_total,'returned_items',jsonb_array_length(p_items),'new_sale_status',v_new_status));
 return jsonb_build_object('return_id',v_return.id,'sale_id',p_sale_id,'returned_items',jsonb_array_length(p_items),'refund_amount',v_refund_total,'total_refunded_for_sale',v_total_refunded,'sale_status',v_new_status,'audit_log_id',v_audit_id);
end;$function$;
 
notify pgrst, 'reload schema';
