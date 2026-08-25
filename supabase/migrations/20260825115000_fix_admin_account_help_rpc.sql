create or replace function public.admin_account_help_target(p_profile_id uuid)
returns table(id uuid, display_name text, role text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() <> 'admin' then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  return query
  select p.id, p.display_name, p.role::text
  from public.profiles p
  where p.id = p_profile_id
    and p.is_active = true
  limit 1;
end;
$$;

create or replace function public.admin_prepare_account_help(
  p_request_id uuid,
  p_profile_id uuid,
  p_phone text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if public.current_user_role() <> 'admin' then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  select p.role::text into v_role
  from public.profiles p
  where p.id = p_profile_id and p.is_active = true;

  if v_role is null or not exists (
    select 1 from public.account_help_requests r
    where r.id = p_request_id and r.status = 'pending'
  ) then
    return false;
  end if;

  update public.profiles
  set phone = p_phone, must_change_password = true
  where id = p_profile_id;

  if v_role = 'student' then
    update public.students set phone = p_phone where profile_id = p_profile_id;
  elsif v_role = 'guardian' then
    update public.guardians set phone = p_phone where profile_id = p_profile_id;
  end if;

  return true;
end;
$$;

create or replace function public.admin_finish_account_help(
  p_request_id uuid,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() <> 'admin' then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  update public.account_help_requests
  set profile_id = p_profile_id,
      status = 'completed',
      processed_at = now(),
      processed_by = auth.uid()
  where id = p_request_id and status = 'pending';

  return found;
end;
$$;

grant execute on function public.admin_account_help_target(uuid) to authenticated;
grant execute on function public.admin_prepare_account_help(uuid, uuid, text) to authenticated;
grant execute on function public.admin_finish_account_help(uuid, uuid) to authenticated;
