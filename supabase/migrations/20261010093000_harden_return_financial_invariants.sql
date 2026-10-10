-- Harden financial invariants in sale/purchase returns and historical cost tracking.
-- This migration changes function definitions only; it does not rewrite financial rows.

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
  v_occurrences integer;
begin
  -- Unknown-cost items must remain unknown in the historical sale line.
  v_def := pg_get_functiondef('private.create_sale_transaction(uuid,uuid,text,bigint,jsonb,numeric,numeric,numeric,text,text,text)'::regprocedure);
  v_old := $old$v_item.quantity, v_item.discount, v_item_total,
      v_unit_cost, v_cost_total$old$;
  v_new := $new$v_item.quantity, v_item.discount, v_item_total,
      case when v_cost_known then v_unit_cost else null end, v_cost_total$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one cost-storage pattern in create_sale_transaction; found %', v_occurrences; end if;
  execute replace(v_def, v_old, v_new);

  -- Sale returns: cap refunds by the returned share of the invoice total, including
  -- invoice-level discount/tax, and preserve existing cost knowledge when historical
  -- unit cost is unknown.
  v_def := pg_get_functiondef('private.return_sale_items(uuid,uuid,bigint,jsonb,text,text,numeric,text,text)'::regprocedure);

  v_old := $old$ v_item jsonb; v_sale_item public.sale_items%rowtype; v_store_product public.store_products%rowtype;
 v_return_qty integer; v_refund numeric; v_total_refunded numeric:=0; v_previous_return_qty integer:=0;
 v_payment_total numeric:=0; v_refundable_payment numeric:=0; v_new_status text; v_audit_id bigint;$old$;
  v_new := $new$ v_item jsonb; v_sale_item public.sale_items%rowtype; v_store_product public.store_products%rowtype;
 v_return_qty integer; v_refund numeric; v_total_refunded numeric:=0; v_previous_return_qty integer:=0;
 v_payment_total numeric:=0; v_refundable_payment numeric:=0; v_new_status text; v_audit_id bigint;
 v_returnable_value numeric:=0; v_prior_return_value numeric:=0; v_item_return_value numeric:=0;
 v_refund_total numeric:=coalesce(p_refund_amount,0);$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one declaration pattern in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if p_refund_amount>0 and not private.has_org_permission(p_organization_id,'payments.refund') then raise exception 'missing permission: payments.refund'; end if;$old$;
  v_new := $new$if v_refund_total>0 and not private.has_org_permission(p_organization_id,'payments.refund') then raise exception 'missing permission: payments.refund'; end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one refund permission check in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if p_refund_amount<0 then raise exception 'refund amount cannot be negative'; end if;$old$;
  v_new := $new$if v_refund_total<0 then raise exception 'refund amount cannot be negative'; end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one refund validation in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if p_refund_amount>v_refundable_payment then raise exception 'refund exceeds refundable payment balance'; end if;$old$;
  v_new := $new$if v_refund_total>v_refundable_payment then raise exception 'refund exceeds refundable payment balance'; end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one refundable-balance check in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if v_return_qty+v_previous_return_qty>v_sale_item.quantity then raise exception 'return quantity exceeds sold quantity for sale item %',v_sale_item.id; end if;
   if v_refund>(v_sale_item.unit_price*v_return_qty) then raise exception 'item refund exceeds returned item value'; end if;$old$;
  v_new := $new$if v_return_qty+v_previous_return_qty>v_sale_item.quantity then raise exception 'return quantity exceeds sold quantity for sale item %',v_sale_item.id; end if;
   if v_sale.subtotal > 0 then
     v_prior_return_value := round(((v_sale_item.total * v_sale.total / v_sale.subtotal) * v_previous_return_qty) / v_sale_item.quantity, 2);
     v_item_return_value := round(((v_sale_item.total * v_sale.total / v_sale.subtotal) * (v_previous_return_qty + v_return_qty)) / v_sale_item.quantity, 2) - v_prior_return_value;
   else
     v_prior_return_value := 0;
     v_item_return_value := 0;
   end if;
   v_returnable_value := v_returnable_value + v_item_return_value;
   if v_refund > v_item_return_value then raise exception 'item refund exceeds returned item value after invoice discounts and tax'; end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one return value check in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$end loop;
 insert into public.sale_returns$old$;
  v_new := $new$end loop;
 if v_refund_total > v_returnable_value then raise exception 'refund exceeds the net value of returned items'; end if;
 if v_refund_total > 0 and nullif(btrim(coalesce(p_refund_payment_method,'')),'') is null then raise exception 'refund payment method is required'; end if;
 insert into public.sale_returns$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one return insertion point in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if p_refund_amount>0 then$old$;
  v_new := $new$if v_refund_total>0 then$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one refund insert condition in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$values(p_sale_id,p_organization_id,p_store_id,p_refund_amount,p_refund_payment_method,p_refund_reference,coalesce(p_reason,'Sale item return'));$old$;
  v_new := $new$values(p_sale_id,p_organization_id,p_store_id,v_refund_total,p_refund_payment_method,p_refund_reference,coalesce(p_reason,'Sale item return'));$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one refund insert in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$'refund_amount',p_refund_amount$old$;
  v_new := $new$'refund_amount',v_refund_total$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 2 then raise exception 'Expected two refund output values in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if v_store_product.quantity <= 0 and v_sale_item.unit_cost is not null then$old$;
  v_new := $new$if v_sale_item.cost_total is not null and v_sale_item.unit_cost is not null and v_store_product.quantity <= 0 then$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one first cost branch in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$elsif v_store_product.cost_known and v_sale_item.unit_cost is not null then$old$;
  v_new := $new$elsif v_sale_item.cost_total is not null and v_sale_item.unit_cost is not null and v_store_product.cost_known then$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one second cost branch in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$     else
       update public.store_products set quantity=quantity+v_return_qty,average_cost=0,cost_known=false,updated_at=now() where id=v_store_product.id;
     end if;$old$;
  v_new := $new$     elsif v_sale_item.cost_total is null or v_sale_item.unit_cost is null then
       update public.store_products set quantity=quantity+v_return_qty,updated_at=now() where id=v_store_product.id;
     else
       update public.store_products set quantity=quantity+v_return_qty,average_cost=0,cost_known=false,updated_at=now() where id=v_store_product.id;
     end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one cost fallback in return_sale_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  execute v_def;

  -- A cash refund against a purchase return cannot exceed the amount actually paid
  -- and allocated to that receipt, net of prior supplier refunds.
  v_def := pg_get_functiondef('private.return_purchase_items(uuid,uuid,bigint,jsonb,text,numeric,text,text,text)'::regprocedure);

  v_old := $old$v_refund numeric := coalesce(p_refund_amount,0);$old$;
  v_new := $new$v_refund numeric := coalesce(p_refund_amount,0);
  v_paid_allocated numeric := 0;
  v_prior_supplier_refunds numeric := 0;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one refund declaration in return_purchase_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'return items are required'; end if;$old$;
  v_new := $new$if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'return items are required'; end if;
  if exists (
    select 1
    from jsonb_array_elements(p_items) x
    group by (x->>'purchase_receipt_item_id')
    having count(*) > 1
  ) then raise exception 'duplicate purchase receipt item in return request'; end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one items validation in return_purchase_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if v_refund > v_total then raise exception 'refund amount cannot exceed returned purchase value'; end if;$old$;
  v_new := $new$if v_refund > v_total then raise exception 'refund amount cannot exceed returned purchase value'; end if;

  select coalesce(sum(a.amount), 0)
    into v_paid_allocated
    from public.supplier_payment_allocations a
   where a.purchase_receipt_id = v_purchase.id
     and a.organization_id = p_organization_id;

  select coalesce(sum(sr.amount), 0)
    into v_prior_supplier_refunds
    from public.supplier_refunds sr
    join public.purchase_returns pr on pr.id = sr.purchase_return_id
   where pr.purchase_receipt_id = v_purchase.id
     and pr.organization_id = p_organization_id
     and pr.status = 'completed';

  if v_refund > greatest(v_paid_allocated - v_prior_supplier_refunds, 0) then
    raise exception 'supplier refund exceeds the amount paid for this purchase';
  end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one supplier refund cap in return_purchase_items; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  execute v_def;

  -- Preserve known current inventory valuation when a returned/cancelled sale line
  -- had unknown historical cost. A NULL cost_total is the authoritative unknown-cost
  -- marker; unit_cost may be zero in legacy rows and must not be treated as known.
  v_def := pg_get_functiondef('private.cancel_sale(uuid,bigint,text,text,text)'::regprocedure);

  v_old := $old$select si.product_id, si.quantity, si.unit_cost
    from public.sale_items si$old$;
  v_new := $new$select si.product_id, si.quantity, si.unit_cost, si.cost_total
    from public.sale_items si$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one sale item query in refund-aware cancellation; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$if v_item.unit_cost is not null then$old$;
  v_new := $new$if v_item.cost_total is not null and v_item.unit_cost is not null then$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one cost condition in refund-aware cancellation; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  v_old := $old$      end if;
    else
      v_new_cost := 0;
      v_new_cost_known := false;
    end if;$old$;
  v_new := $new$      end if;
    else
      v_new_cost := v_balance.average_cost;
      v_new_cost_known := v_balance.cost_known;
    end if;$new$;
  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then raise exception 'Expected one unknown-cost fallback in refund-aware cancellation; found %', v_occurrences; end if;
  v_def := replace(v_def, v_old, v_new);

  execute v_def;
end;
$migration$;
