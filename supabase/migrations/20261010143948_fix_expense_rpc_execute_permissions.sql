-- Restore authenticated execution through the public expense RPC wrappers.
-- Add the missing authorization check to expense cancellation.
-- No expense or other business rows are changed by this migration.

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
  v_occurrences integer;
begin
  v_def := pg_get_functiondef(
    'private.cancel_expense(uuid,bigint,text)'::regprocedure
  );

  v_old := $old$ if not found or not private.is_org_store_member(p_organization_id,v.store_id) then raise exception 'expense not found or access denied'; end if;$old$;
  v_new := $new$ if not found or not private.is_org_store_member(p_organization_id,v.store_id) then raise exception 'expense not found or access denied'; end if;
 if not private.has_org_permission(p_organization_id,'expenses.create') then
   raise exception 'expenses.create permission required';
 end if;$new$;

  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'Expected one authorization insertion point in cancel_expense; found %; no change applied', v_occurrences;
  end if;

  v_def := replace(v_def, v_old, v_new);
  if position('expenses.create permission required' in v_def) = 0 then
    raise exception 'Expense cancellation permission validation failed; no change applied';
  end if;
  execute v_def;
end;
$migration$;

-- The public wrappers are SECURITY INVOKER functions, so authenticated callers must
-- have EXECUTE on the internal SECURITY DEFINER functions they invoke.
revoke execute on function private.create_expense(uuid,uuid,text,numeric,date,text,text,text) from public, anon;
revoke execute on function private.cancel_expense(uuid,bigint,text) from public, anon;
grant execute on function private.create_expense(uuid,uuid,text,numeric,date,text,text,text) to authenticated;
grant execute on function private.cancel_expense(uuid,bigint,text) to authenticated;

revoke execute on function public.create_expense(uuid,uuid,text,numeric,date,text,text,text) from public, anon;
revoke execute on function public.cancel_expense(uuid,bigint,text) from public, anon;
grant execute on function public.create_expense(uuid,uuid,text,numeric,date,text,text,text) to authenticated;
grant execute on function public.cancel_expense(uuid,bigint,text) to authenticated;
