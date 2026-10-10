-- Restrict application RPC wrappers and their internal helpers to signed-in users.
-- The functions already enforce organization permissions; this also prevents anonymous
-- clients from invoking these endpoints at all.
revoke execute on function public.assign_member_role(uuid, uuid, uuid) from public, anon;
revoke execute on function public.create_product_for_store_with_cost(uuid, uuid, text, numeric, integer, integer, text, numeric) from public, anon;
revoke execute on function public.list_organization_members(uuid) from public, anon;
revoke execute on function public.set_member_status(uuid, uuid, text) from public, anon;
revoke execute on function public.set_member_stores(uuid, uuid, uuid[]) from public, anon;

grant execute on function public.assign_member_role(uuid, uuid, uuid) to authenticated;
grant execute on function public.create_product_for_store_with_cost(uuid, uuid, text, numeric, integer, integer, text, numeric) to authenticated;
grant execute on function public.list_organization_members(uuid) to authenticated;
grant execute on function public.set_member_status(uuid, uuid, text) to authenticated;
grant execute on function public.set_member_stores(uuid, uuid, uuid[]) to authenticated;

-- Keep the internal SECURITY DEFINER helpers unavailable to anonymous callers as well.
revoke execute on function private.assign_member_role(uuid, uuid, uuid) from public, anon;
revoke execute on function private.create_product_for_store_with_cost(uuid, uuid, text, numeric, integer, integer, text, numeric) from public, anon;
revoke execute on function private.list_organization_members(uuid) from public, anon;
revoke execute on function private.set_member_status(uuid, uuid, text) from public, anon;
revoke execute on function private.set_member_stores(uuid, uuid, uuid[]) from public, anon;
revoke execute on function private.prevent_supplier_purchase_financial_hard_delete() from public, anon;

grant execute on function private.assign_member_role(uuid, uuid, uuid) to authenticated;
grant execute on function private.create_product_for_store_with_cost(uuid, uuid, text, numeric, integer, integer, text, numeric) to authenticated;
grant execute on function private.list_organization_members(uuid) to authenticated;
grant execute on function private.set_member_status(uuid, uuid, text) to authenticated;
grant execute on function private.set_member_stores(uuid, uuid, uuid[]) to authenticated;
