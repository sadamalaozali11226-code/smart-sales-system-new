begin;

alter function public.list_organization_members(uuid)
  set search_path = public;

alter function public.assign_member_role(uuid, uuid, uuid)
  set search_path = public;

alter function public.set_member_stores(uuid, uuid, uuid[])
  set search_path = public;

alter function public.set_member_status(uuid, uuid, text)
  set search_path = public;

commit;
