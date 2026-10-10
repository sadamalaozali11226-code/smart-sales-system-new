-- Restrict SECURITY DEFINER report RPCs to users with report permission.
-- Organization-wide reports require explicit store-management authority.
-- This migration changes function definitions only; it does not modify business rows.

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
  v_occurrences integer;
begin
  -- Commercial dashboard: retain organization membership checks, require reports.read,
  -- and prevent a store-scoped member from omitting p_store_id to read every store.
  v_def := pg_get_functiondef(
    'private.commercial_reports_summary(uuid,uuid,date,date)'::regprocedure
  );

  v_old := $old$  if p_store_id is not null and not private.is_org_store_member(p_organization_id,p_store_id) then raise exception 'Store access denied'; end if;$old$;
  v_new := $new$  if not private.has_org_permission(p_organization_id,'reports.read') then
    raise exception 'Reports permission required';
  end if;
  if p_store_id is null then
    if not private.has_org_permission(p_organization_id,'stores.manage') then
      raise exception 'Organization-wide report access denied';
    end if;
  elsif not private.is_org_store_member(p_organization_id,p_store_id) then
    raise exception 'Store access denied';
  end if;$new$;

  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'Expected one store authorization block in commercial_reports_summary; found %; no change applied', v_occurrences;
  end if;
  v_def := replace(v_def, v_old, v_new);
  if position('Reports permission required' in v_def) = 0
     or position('Organization-wide report access denied' in v_def) = 0 then
    raise exception 'Commercial report authorization validation failed; no change applied';
  end if;
  execute v_def;

  -- Profitability report uses the same store-scoping rules.
  v_def := pg_get_functiondef(
    'private.profitability_summary(uuid,uuid,date,date)'::regprocedure
  );

  v_old := $old$ if p_store_id is not null and not private.is_org_store_member(p_organization_id,p_store_id) then
   raise exception 'Store access denied';
 end if;$old$;
  v_new := $new$ if not private.has_org_permission(p_organization_id,'reports.read') then
   raise exception 'Reports permission required';
 end if;
 if p_store_id is null then
   if not private.has_org_permission(p_organization_id,'stores.manage') then
     raise exception 'Organization-wide report access denied';
   end if;
 elsif not private.is_org_store_member(p_organization_id,p_store_id) then
   raise exception 'Store access denied';
 end if;$new$;

  v_occurrences := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_occurrences <> 1 then
    raise exception 'Expected one store authorization block in profitability_summary; found %; no change applied', v_occurrences;
  end if;
  v_def := replace(v_def, v_old, v_new);
  if position('Reports permission required' in v_def) = 0
     or position('Organization-wide report access denied' in v_def) = 0 then
    raise exception 'Profitability authorization validation failed; no change applied';
  end if;
  execute v_def;
end;
$migration$;
