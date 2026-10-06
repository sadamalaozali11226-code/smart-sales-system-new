-- Commercial V1 security hardening: internal purchase-return numbering must not be callable by API roles.
revoke execute on function private.next_purchase_return_number(uuid) from public, anon, authenticated;
