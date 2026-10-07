-- Add explicit permission for creating expenses and enforce it in the privileged mutation.
insert into public.permissions(code, description)
values ('expenses.create', 'Create expense records')
on conflict (code) do nothing;

insert into public.role_permissions(role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'expenses.create'
where r.code = 'owner'
on conflict do nothing;

create or replace function private.create_expense(
  p_organization_id uuid,
  p_store_id uuid,
  p_category text,
  p_amount numeric,
  p_expense_date date default current_date,
  p_payment_method text default 'cash',
  p_reference text default null,
  p_notes text default null
) returns public.expenses
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v public.expenses;
begin
  if auth.uid() is null or not private.is_org_store_member(p_organization_id,p_store_id) then
    raise exception 'access denied';
  end if;
  if not private.has_org_permission(p_organization_id,'expenses.create') then
    raise exception 'expenses.create permission required';
  end if;
  if coalesce(trim(p_category),'')='' then raise exception 'expense category is required'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'expense amount must be greater than zero'; end if;

  insert into public.expenses(
    organization_id,store_id,expense_number,category,amount,expense_date,
    payment_method,reference,notes,status,created_by
  )
  values(
    p_organization_id,p_store_id,private.next_expense_number(p_organization_id),
    trim(p_category),round(p_amount,2),coalesce(p_expense_date,current_date),
    coalesce(nullif(trim(p_payment_method),''),'cash'),
    nullif(trim(p_reference),''),nullif(trim(p_notes),''),'completed',auth.uid()
  )
  returning * into v;

  insert into public.audit_logs(
    organization_id,store_id,actor_user_id,action,entity_type,entity_id,metadata
  )
  values(
    p_organization_id,p_store_id,auth.uid(),'expense.created','expense',v.id::text,
    jsonb_build_object('amount',v.amount,'category',v.category)
  );

  return v;
end
$function$;
