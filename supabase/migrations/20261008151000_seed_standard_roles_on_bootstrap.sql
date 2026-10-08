begin;

create or replace function private.bootstrap_organization(
  p_organization_name text,
  p_slug text,
  p_store_name text,
  p_store_code text
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_user_id uuid;
  v_org_id uuid;
  v_store_id uuid;
  v_role_id uuid;
  v_member_id uuid;
  v_slug text;
  v_store_code text;
  v_permission_count integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'authenticated user required'; end if;
  if nullif(trim(p_organization_name), '') is null then raise exception 'organization name is required'; end if;

  v_slug := lower(trim(p_slug));
  if v_slug !~ '^[a-z0-9][a-z0-9_-]{1,48}[a-z0-9]$' then raise exception 'invalid organization slug'; end if;

  if nullif(trim(p_store_name), '') is null then raise exception 'store name is required'; end if;
  v_store_code := lower(trim(p_store_code));
  if v_store_code !~ '^[a-z0-9][a-z0-9_-]{1,48}[a-z0-9]$' then raise exception 'invalid store code'; end if;

  if exists (
    select 1 from public.organization_members om
    where om.user_id = v_user_id and om.status = 'active'
  ) then raise exception 'user already has an active organization membership'; end if;

  if exists (select 1 from public.organizations o where o.slug = v_slug) then
    raise exception 'organization slug already exists';
  end if;

  insert into public.organizations (name, slug)
  values (trim(p_organization_name), v_slug)
  returning id into v_org_id;

  insert into public.stores (organization_id, name, code)
  values (v_org_id, trim(p_store_name), v_store_code)
  returning id into v_store_id;

  insert into public.roles (organization_id, name, code, is_system)
  values (v_org_id, 'Owner', 'owner', true)
  returning id into v_role_id;

  insert into public.organization_members (organization_id, user_id, role_id, status)
  values (v_org_id, v_user_id, v_role_id, 'active')
  returning id into v_member_id;

  insert into public.role_permissions (role_id, permission_id)
  select v_role_id, p.id from public.permissions p on conflict do nothing;

  select count(*) into v_permission_count
  from public.role_permissions rp where rp.role_id = v_role_id;

  if v_permission_count = 0 then raise exception 'permission catalog is empty'; end if;

  insert into public.member_stores (member_id, store_id)
  values (v_member_id, v_store_id);

  insert into public.roles (organization_id, name, code, is_system)
  values
    (v_org_id,'المدير العام','general_manager',false),
    (v_org_id,'مدير فرع','branch_manager',false),
    (v_org_id,'محاسب','accountant',false),
    (v_org_id,'أمين مخزن','warehouse_keeper',false),
    (v_org_id,'كاشير','cashier',false),
    (v_org_id,'موظف مبيعات','sales_employee',false)
  on conflict (organization_id,code) do nothing;

  insert into public.role_permissions(role_id,permission_id)
  select r.id,p.id from public.roles r join public.permissions p on p.code in (
    'customers.create','customers.read','customers.update','expenses.create',
    'inventory.adjust','inventory.read','payments.create','payments.refund',
    'products.create','products.read','products.update',
    'purchases.cancel','purchases.create','purchases.view','reports.read',
    'sales.cancel','sales.create','sales.read','sales.update',
    'supplier_payments.create','suppliers.manage','suppliers.view')
  where r.organization_id=v_org_id and r.code in ('general_manager','branch_manager')
  on conflict do nothing;

  insert into public.role_permissions(role_id,permission_id)
  select r.id,p.id from public.roles r join public.permissions p on p.code in (
    'customers.read','expenses.create','payments.create','payments.refund',
    'purchases.cancel','purchases.create','purchases.view','reports.read',
    'sales.read','sales.update','supplier_payments.create','suppliers.view')
  where r.organization_id=v_org_id and r.code='accountant'
  on conflict do nothing;

  insert into public.role_permissions(role_id,permission_id)
  select r.id,p.id from public.roles r join public.permissions p on p.code in (
    'inventory.adjust','inventory.read','products.read',
    'purchases.create','purchases.cancel','purchases.view','suppliers.view')
  where r.organization_id=v_org_id and r.code='warehouse_keeper'
  on conflict do nothing;

  insert into public.role_permissions(role_id,permission_id)
  select r.id,p.id from public.roles r join public.permissions p on p.code in (
    'customers.create','customers.read','customers.update','payments.create',
    'products.read','sales.create','sales.read','sales.update')
  where r.organization_id=v_org_id and r.code in ('cashier','sales_employee')
  on conflict do nothing;

  return jsonb_build_object(
    'organization_id', v_org_id,
    'store_id', v_store_id,
    'role_id', v_role_id,
    'member_id', v_member_id,
    'permissions_assigned', v_permission_count
  );
end;
$function$;

commit;
