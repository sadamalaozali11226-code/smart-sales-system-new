-- Commercial V1 security hardening: public RPC execute privileges.
-- Anonymous clients must not be able to invoke account-changing/reporting RPCs.
-- Authenticated access remains explicit for application-facing wrappers.

revoke execute on function public.cancel_expense(uuid,bigint,text) from public;
revoke execute on function public.create_expense(uuid,uuid,text,numeric,date,text,text,text) from public;
revoke execute on function public.commercial_reports(uuid,uuid,date,date) from public;
revoke execute on function public.customer_account_summary(uuid,uuid) from public;
revoke execute on function public.customer_statement(uuid,bigint,uuid,date,date) from public;
revoke execute on function public.supplier_account_summary(uuid,uuid) from public;
revoke execute on function public.supplier_statement(uuid,bigint,date,date) from public;

revoke execute on function private.cancel_sale(uuid,bigint,text,text,text) from public;
revoke execute on function private.cancel_sale(uuid,bigint,text) from public;
revoke execute on function private.record_sale_payment(bigint,numeric,text,text) from public;
revoke execute on function private.return_purchase_items(uuid,uuid,bigint,jsonb,text,numeric,text,text,text) from public;

grant execute on function private.cancel_sale(uuid,bigint,text) to authenticated;
grant execute on function private.cancel_sale(uuid,bigint,text,text,text) to authenticated;
grant execute on function private.record_sale_payment(bigint,numeric,text,text) to authenticated;
grant execute on function private.return_purchase_items(uuid,uuid,bigint,jsonb,text,numeric,text,text,text) to authenticated;
