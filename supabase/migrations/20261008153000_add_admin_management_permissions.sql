begin;

insert into public.permissions(code,description) values
('members.manage','Manage organization members and assign roles'),
('roles.manage','Manage organization roles and role permissions'),
('stores.manage','Manage organization stores and branch assignments')
on conflict(code) do update set description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('members.manage','roles.manage','stores.manage')
where r.code='owner' on conflict do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.code in ('members.manage','stores.manage')
where r.code='general_manager' on conflict do nothing;

commit;
