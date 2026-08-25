create or replace function public.account_help_request_create(
  p_requester_name text,
  p_account_type text,
  p_registered_phone text,
  p_reachable_phone text,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_name text := trim(coalesce(p_requester_name, ''));
  v_old_phone text := regexp_replace(coalesce(p_registered_phone, ''), '\D', '', 'g');
  v_reachable_phone text := regexp_replace(coalesce(p_reachable_phone, ''), '\D', '', 'g');
  v_profile_id uuid;
begin
  if length(v_name) < 2
     or p_account_type not in ('student', 'guardian', 'staff')
     or p_reason not in ('phone_changed', 'sms_unavailable', 'other')
     or length(v_reachable_phone) not between 10 and 11 then
    raise exception 'INVALID_HELP_REQUEST';
  end if;

  if exists (
    select 1
    from public.account_help_requests
    where regexp_replace(reachable_phone, '\D', '', 'g') = v_reachable_phone
      and requested_at > now() - interval '1 minute'
  ) then
    raise exception 'RATE_LIMIT_MINUTE';
  end if;

  if (
    select count(*)
    from public.account_help_requests
    where regexp_replace(reachable_phone, '\D', '', 'g') = v_reachable_phone
      and requested_at > now() - interval '1 hour'
  ) >= 5 then
    raise exception 'RATE_LIMIT_HOUR';
  end if;

  select p.id
    into v_profile_id
  from public.profiles p
  where p.is_active = true
    and lower(trim(p.display_name)) = lower(v_name)
    and (
      v_old_phone = ''
      or regexp_replace(coalesce(p.phone, ''), '\D', '', 'g') = v_old_phone
      or exists (
        select 1 from public.students s
        where s.profile_id = p.id
          and regexp_replace(coalesce(s.phone, ''), '\D', '', 'g') = v_old_phone
      )
      or exists (
        select 1 from public.guardians g
        where g.profile_id = p.id
          and regexp_replace(coalesce(g.phone, ''), '\D', '', 'g') = v_old_phone
      )
    )
  order by p.created_at
  limit 1;

  insert into public.account_help_requests (
    id,
    requester_name,
    account_type,
    registered_phone,
    reachable_phone,
    reason,
    profile_id
  )
  values (
    v_id,
    v_name,
    p_account_type,
    nullif(v_old_phone, ''),
    v_reachable_phone,
    p_reason,
    v_profile_id
  );

  return v_id;
end;
$$;

revoke all on function public.account_help_request_create(text, text, text, text, text) from public;
grant execute on function public.account_help_request_create(text, text, text, text, text) to anon, authenticated;
