begin;

create or replace function private.list_organization_members(p_organization_id uuid)
returns table(member_id uuid,user_id uuid,status text,role_id uuid,role_name text,role_code text,store_ids uuid[],store_names text[])
language plpgsql security definer set search_path='public','private'
as $function$
begin
  if auth.uid() is null or not private.is_org_member(p_organization_id) then raise exception 'not authorized'; end if;
  if not private.has_org_permission(p_organization_id,'members.manage')
     and not private.has_org_permission(p_organization_id,'roles.manage')
     and not private.has_org_permission(p_organization_id,'stores.manage') then raise exception 'permission denied'; end if;
  return query
  select om.id,om.user_id,om.status,r.id,r.name,r.code,
    coalesce(array_agg(ms.store_id) filter(where ms.store_id is not null),'{}'::uuid[]),
    coalesce(array_agg(s.name order by s.name) filter(where s.id is not null),'{}'::text[])
  from public.organization_members om
  join public.roles r on r.id=om.role_id and r.organization_id=p_organization_id
  left join public.member_stores ms on ms.member_id=om.id
  left join public.stores s on s.id=ms.store_id and s.organization_id=p_organization_id
  where om.organization_id=p_organization_id
  group by om.id,om.user_id,om.status,r.id,r.name,r.code
  order by om.created_at;
end;$function$;

create or replace function private.assign_member_role(p_organization_id uuid,p_member_id uuid,p_role_id uuid)
returns void language plpgsql security definer set search_path='public','private'
as $function$
declare v_target_code text; v_actor_code text; v_owner_count integer;
begin
  if auth.uid() is null or not private.has_org_permission(p_organization_id,'members.manage') then raise exception 'permission denied'; end if;
  select r.code into v_target_code from public.roles r where r.id=p_role_id and r.organization_id=p_organization_id;
  if v_target_code is null then raise exception 'invalid role'; end if;
  select r.code into v_actor_code from public.organization_members om join public.roles r on r.id=om.role_id
    where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.status='active';
  if v_target_code='owner' and v_actor_code<>'owner' then raise exception 'only owner can assign owner role'; end if;
  if not exists(select 1 from public.organization_members where id=p_member_id and organization_id=p_organization_id) then raise exception 'member not found'; end if;
  if v_actor_code<>'owner' and exists(select 1 from public.organization_members om join public.roles r on r.id=om.role_id where om.id=p_member_id and r.code='owner') then raise exception 'cannot change owner role'; end if;
  if v_actor_code='owner' and exists(select 1 from public.organization_members om join public.roles r on r.id=om.role_id where om.id=p_member_id and r.code='owner') then
    select count(*) into v_owner_count from public.organization_members om join public.roles r on r.id=om.role_id
      where om.organization_id=p_organization_id and om.status='active' and r.code='owner';
    if v_owner_count<=1 and v_target_code<>'owner' then raise exception 'cannot remove the last active owner'; end if;
  end if;
  update public.organization_members set role_id=p_role_id where id=p_member_id and organization_id=p_organization_id;
end;$function$;

create or replace function private.set_member_stores(p_organization_id uuid,p_member_id uuid,p_store_ids uuid[])
returns void language plpgsql security definer set search_path='public','private'
as $function$
begin
  if auth.uid() is null or not private.has_org_permission(p_organization_id,'stores.manage') then raise exception 'permission denied'; end if;
  if not exists(select 1 from public.organization_members where id=p_member_id and organization_id=p_organization_id) then raise exception 'member not found'; end if;
  if exists(select 1 from unnest(coalesce(p_store_ids,'{}'::uuid[])) x(id) left join public.stores s on s.id=x.id and s.organization_id=p_organization_id where s.id is null) then raise exception 'invalid store for organization'; end if;
  delete from public.member_stores where member_id=p_member_id;
  insert into public.member_stores(member_id,store_id) select p_member_id,x.id from unnest(coalesce(p_store_ids,'{}'::uuid[])) x(id) on conflict do nothing;
end;$function$;

create or replace function private.set_member_status(p_organization_id uuid,p_member_id uuid,p_status text)
returns void language plpgsql security definer set search_path='public','private'
as $function$
declare v_owner_count integer;
begin
  if auth.uid() is null or not private.has_org_permission(p_organization_id,'members.manage') then raise exception 'permission denied'; end if;
  if p_status not in ('active','inactive') then raise exception 'invalid member status'; end if;
  if not exists(select 1 from public.organization_members where id=p_member_id and organization_id=p_organization_id) then raise exception 'member not found'; end if;
  if p_status='inactive' and exists(select 1 from public.organization_members om join public.roles r on r.id=om.role_id where om.id=p_member_id and r.code='owner') then
    select count(*) into v_owner_count from public.organization_members om join public.roles r on r.id=om.role_id where om.organization_id=p_organization_id and om.status='active' and r.code='owner';
    if v_owner_count<=1 then raise exception 'cannot deactivate the last active owner'; end if;
    if not exists(select 1 from public.organization_members me join public.roles rr on rr.id=me.role_id where me.organization_id=p_organization_id and me.user_id=auth.uid() and me.status='active' and rr.code='owner') then raise exception 'only owner can deactivate owner'; end if;
  end if;
  update public.organization_members set status=p_status where id=p_member_id and organization_id=p_organization_id;
end;$function$;

create or replace function public.list_organization_members(p_organization_id uuid)
returns table(member_id uuid,user_id uuid,status text,role_id uuid,role_name text,role_code text,store_ids uuid[],store_names text[])
language sql security invoker as $$ select * from private.list_organization_members(p_organization_id); $$;
create or replace function public.assign_member_role(p_organization_id uuid,p_member_id uuid,p_role_id uuid)
returns void language sql security invoker as $$ select private.assign_member_role(p_organization_id,p_member_id,p_role_id); $$;
create or replace function public.set_member_stores(p_organization_id uuid,p_member_id uuid,p_store_ids uuid[])
returns void language sql security invoker as $$ select private.set_member_stores(p_organization_id,p_member_id,p_store_ids); $$;
create or replace function public.set_member_status(p_organization_id uuid,p_member_id uuid,p_status text)
returns void language sql security invoker as $$ select private.set_member_status(p_organization_id,p_member_id,p_status); $$;

revoke all on function public.list_organization_members(uuid) from public;
revoke all on function public.assign_member_role(uuid,uuid,uuid) from public;
revoke all on function public.set_member_stores(uuid,uuid,uuid[]) from public;
revoke all on function public.set_member_status(uuid,uuid,text) from public;
grant execute on function public.list_organization_members(uuid) to authenticated;
grant execute on function public.assign_member_role(uuid,uuid,uuid) to authenticated;
grant execute on function public.set_member_stores(uuid,uuid,uuid[]) to authenticated;
grant execute on function public.set_member_status(uuid,uuid,text) to authenticated;

commit;
