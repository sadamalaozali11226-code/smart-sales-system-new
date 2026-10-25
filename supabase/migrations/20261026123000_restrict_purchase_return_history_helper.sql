-- Restrict the SECURITY DEFINER helper to authenticated callers only.
-- The public wrapper performs its own grant check and forwards authenticated calls.
revoke execute on function private.purchase_return_history(uuid, uuid, bigint) from public, anon;
grant execute on function private.purchase_return_history(uuid, uuid, bigint) to authenticated;
