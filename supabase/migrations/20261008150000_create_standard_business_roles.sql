begin;

insert into public.roles (organization_id, name, code, is_system)
values
  ('9e7c7504-0d5b-4589-84ac-f884b8a2712d','المدير العام','general_manager',false),
  ('9e7c7504-0d5b-4589-84ac-f884b8a2712d','مدير فرع','branch_manager',false),
  ('9e7c7504-0d5b-4589-84ac-f884b8a2712d','محاسب','accountant',false),
  ('9e7c7504-0d5b-4589-84ac-f884b8a2712d','أمين مخزن','warehouse_keeper',false),
  ('9e7c7504-0d5b-4589-84ac-f884b8a2712d','كاشير','cashier',false),
  ('9e7c7504-0d5b-4589-84ac-f884b8a2712d','موظف مبيعات','sales_employee',false)
on conflict (organization_id, code) do update set name=excluded.name;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'customers.create','customers.read','customers.update','expenses.create',
  'inventory.adjust','inventory.read','payments.create','payments.refund',
  'products.create','products.read','products.update',
  'purchases.cancel','purchases.create','purchases.view','reports.read',
  'sales.cancel','sales.create','sales.read','sales.update',
  'supplier_payments.create','suppliers.manage','suppliers.view')
where r.organization_id='9e7c7504-0d5b-4589-84ac-f884b8a2712d'
and r.code in ('general_manager','branch_manager') on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'customers.read','expenses.create','payments.create','payments.refund',
  'purchases.cancel','purchases.create','purchases.view','reports.read',
  'sales.read','sales.update','supplier_payments.create','suppliers.view')
where r.organization_id='9e7c7504-0d5b-4589-84ac-f884b8a2712d'
and r.code='accountant' on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'inventory.adjust','inventory.read','products.read',
  'purchases.create','purchases.cancel','purchases.view','suppliers.view')
where r.organization_id='9e7c7504-0d5b-4589-84ac-f884b8a2712d'
and r.code='warehouse_keeper' on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'customers.create','customers.read','customers.update','payments.create',
  'products.read','sales.create','sales.read','sales.update')
where r.organization_id='9e7c7504-0d5b-4589-84ac-f884b8a2712d'
and r.code in ('cashier','sales_employee') on conflict do nothing;

commit;
