begin;

insert into public.roles (organization_id, name, code, is_system)
select o.id, v.name, v.code, false
from public.organizations o
cross join (values
  ('المدير العام','general_manager'),
  ('مدير فرع','branch_manager'),
  ('محاسب','accountant'),
  ('أمين مخزن','warehouse_keeper'),
  ('كاشير','cashier'),
  ('موظف مبيعات','sales_employee')
) v(name,code)
where o.status='active'
on conflict (organization_id, code) do update set name=excluded.name;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'customers.create','customers.read','customers.update','expenses.create',
  'inventory.adjust','inventory.read','payments.create','payments.refund',
  'products.create','products.read','products.update',
  'purchases.cancel','purchases.create','purchases.view','reports.read',
  'sales.cancel','sales.create','sales.read','sales.update',
  'supplier_payments.create','suppliers.manage','suppliers.view')
where r.code in ('general_manager','branch_manager') on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'customers.read','expenses.create','payments.create','payments.refund',
  'purchases.cancel','purchases.create','purchases.view','reports.read',
  'sales.read','sales.update','supplier_payments.create','suppliers.view')
where r.code='accountant' on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'inventory.adjust','inventory.read','products.read',
  'purchases.create','purchases.cancel','purchases.view','suppliers.view')
where r.code='warehouse_keeper' on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in (
  'customers.create','customers.read','customers.update','payments.create',
  'products.read','sales.create','sales.read','sales.update')
where r.code in ('cashier','sales_employee') on conflict do nothing;

commit;
