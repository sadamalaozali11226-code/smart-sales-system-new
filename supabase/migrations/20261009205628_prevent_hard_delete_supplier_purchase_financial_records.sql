create or replace function private.prevent_supplier_purchase_financial_hard_delete()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Hard deletion of supplier purchase financial records is prohibited; use the approved cancellation or reversal workflow.'
    using errcode = '55000';
end;
$function$;

drop trigger if exists prevent_purchase_receipt_hard_delete on public.purchase_receipts;
create trigger prevent_purchase_receipt_hard_delete
before delete on public.purchase_receipts
for each row execute function private.prevent_supplier_purchase_financial_hard_delete();

drop trigger if exists prevent_purchase_receipt_item_hard_delete on public.purchase_receipt_items;
create trigger prevent_purchase_receipt_item_hard_delete
before delete on public.purchase_receipt_items
for each row execute function private.prevent_supplier_purchase_financial_hard_delete();

drop trigger if exists prevent_supplier_payment_hard_delete on public.supplier_payments;
create trigger prevent_supplier_payment_hard_delete
before delete on public.supplier_payments
for each row execute function private.prevent_supplier_purchase_financial_hard_delete();

drop trigger if exists prevent_supplier_payment_allocation_hard_delete on public.supplier_payment_allocations;
create trigger prevent_supplier_payment_allocation_hard_delete
before delete on public.supplier_payment_allocations
for each row execute function private.prevent_supplier_purchase_financial_hard_delete();
