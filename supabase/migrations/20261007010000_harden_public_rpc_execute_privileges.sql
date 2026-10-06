-- Commercial V1 security hardening: public RPC execute privileges.
-- These reporting/account functions must never be callable by anonymous users.
-- Keep authenticated access for the application where explicitly required.

revoke execute on function public.cancel_expense(uuid,bigint,text) from anon;
revoke execute on function public.create_expense(uuid,uuid,text,numeric,date,text,text,text) from anon;
revoke execute on function public.commercial_reports(uuid,uuid,date,date) from anon;
revoke execute on function public.customer_account_summary(uuid,uuid) from anon;
revoke execute on function public.customer_statement(uuid,bigint,uuid,date,date) from anon;
revoke execute on function public.supplier_account_summary(uuid,uuid) from anon;
revoke execute on function public.supplier_statement(uuid,bigint,uuid,date,date) from anon;

-- Defense in depth: internal SECURITY DEFINER routines must not be directly
-- callable by anonymous clients.
revoke execute on function private.cancel_sale(uuid,bigint,text,text,text) from anon;
revoke execute on function private.cancel_sale(uuid,bigint,text) from anon;
revoke execute on function private.record_sale_payment(bigint,numeric,text,text) from anon;
revoke execute on function private.return_purchase_items(uuid,uuid,bigint,jsonb,text,numeric,text,text,text) from anon;
