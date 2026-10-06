-- Commercial V1: harden sale returns API
-- Production function definitions were applied before committing this migration.

create or replace function public.return_sale_items(
  p_organization_id uuid,p_store_id uuid,p_sale_id bigint,p_items jsonb,
  p_reason text default null,p_notes text default null,p_refund_amount numeric default 0,
  p_refund_payment_method text default 'cash',p_refund_reference text default null
) returns jsonb language plpgsql
set search_path='public','private'
as $function$
begin
  return private.return_sale_items(
    p_organization_id,p_store_id,p_sale_id,p_items,p_reason,p_notes,
    p_refund_amount,p_refund_payment_method,p_refund_reference
  );
end;
$function$;

revoke all on function public.return_sale_items(uuid,uuid,bigint,jsonb,text,text,numeric,text,text) from public;
grant execute on function public.return_sale_items(uuid,uuid,bigint,jsonb,text,text,numeric,text,text) to authenticated;
