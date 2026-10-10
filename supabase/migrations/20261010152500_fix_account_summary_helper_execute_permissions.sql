-- Restore the intended authenticated RPC path for customer/supplier summaries and statements.
-- Public wrappers are SECURITY INVOKER, so authenticated callers need EXECUTE on these
-- internal SECURITY DEFINER helpers. Keep anonymous and PUBLIC execution revoked.
revoke execute on function private.customer_account_summary(uuid, uuid) from public, anon;
revoke execute on function private.supplier_account_summary(uuid, uuid) from public, anon;
revoke execute on function private.customer_statement(uuid, bigint, uuid, date, date) from public, anon;
revoke execute on function private.supplier_statement(uuid, bigint, uuid, date, date) from public, anon;

grant execute on function private.customer_account_summary(uuid, uuid) to authenticated;
grant execute on function private.supplier_account_summary(uuid, uuid) to authenticated;
grant execute on function private.customer_statement(uuid, bigint, uuid, date, date) to authenticated;
grant execute on function private.supplier_statement(uuid, bigint, uuid, date, date) to authenticated;
