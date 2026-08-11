-- 관리자 전용 계정 역할·학생/자녀 연결·활성 상태와 변경 이력을 추가합니다.

alter table public.profiles add column is_active boolean not null default true;

create table public.account_change_logs (
  id uuid primary key default gen_random_uuid(),
  changed_by uuid not null references public.profiles(id) on delete restrict,
  target_profile_id uuid not null references public.profiles(id) on delete cascade,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.account_change_logs enable row level security;
create policy "admin_read_account_change_logs" on public.account_change_logs for select to authenticated using (public.current_user_role() = 'admin');
grant select on table public.account_change_logs to authenticated;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and is_active
$$;

create or replace function public.admin_account_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare result jsonb;
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 계정 설정을 확인할 수 있습니다.'; end if;
  select jsonb_build_object(
    'accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'email', coalesce(u.email, '이메일 없음'),
        'displayName', p.display_name,
        'phone', coalesce(p.phone, s.phone, g.phone),
        'role', p.role,
        'isActive', p.is_active,
        'isSelf', p.id = auth.uid(),
        'studentId', s.id,
        'studentName', s.name,
        'guardianId', g.id,
        'children', coalesce((
          select jsonb_agg(jsonb_build_object('id', child.id, 'name', child.name) order by child.name)
          from public.student_guardians sg join public.students child on child.id = sg.student_id
          where sg.guardian_id = g.id
        ), '[]'::jsonb)
      ) order by p.role, p.display_name)
      from public.profiles p
      join auth.users u on u.id = p.id
      left join public.students s on s.profile_id = p.id
      left join public.guardians g on g.profile_id = p.id
    ), '[]'::jsonb),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'profileId', s.profile_id) order by s.name)
      from public.students s where s.status in ('active', '재원')
    ), '[]'::jsonb),
    'logs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', log.id,
        'action', log.action,
        'details', log.details,
        'targetName', target.display_name,
        'changedByName', actor.display_name,
        'createdAt', log.created_at
      ) order by log.created_at desc)
      from (select * from public.account_change_logs order by created_at desc limit 50) log
      join public.profiles target on target.id = log.target_profile_id
      join public.profiles actor on actor.id = log.changed_by
    ), '[]'::jsonb)
  ) into result;
  return result;
end
$$;

create or replace function public.admin_update_account(
  p_profile_id uuid,
  p_display_name text,
  p_phone text,
  p_role public.user_role,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare previous_role public.user_role; previous_active boolean;
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 계정을 변경할 수 있습니다.'; end if;
  if nullif(trim(p_display_name), '') is null then raise exception '표시 이름을 입력해 주세요.'; end if;
  select role, is_active into previous_role, previous_active from public.profiles where id = p_profile_id;
  if previous_role is null then raise exception '계정을 찾을 수 없습니다.'; end if;
  if p_profile_id = auth.uid() and (p_role <> 'admin' or not p_is_active) then raise exception '현재 로그인한 관리자 본인의 역할이나 활성 상태는 변경할 수 없습니다.'; end if;

  if p_role <> 'student' then update public.students set profile_id = null where profile_id = p_profile_id; end if;
  if p_role <> 'guardian' then update public.guardians set profile_id = null where profile_id = p_profile_id; end if;
  if p_role <> 'teacher' then update public.teachers set profile_id = null where profile_id = p_profile_id; end if;

  update public.profiles set display_name = trim(p_display_name), phone = nullif(trim(p_phone), ''), role = p_role, is_active = p_is_active where id = p_profile_id;
  if p_role = 'teacher' and not exists (select 1 from public.teachers t where t.profile_id = p_profile_id) then
    insert into public.teachers(profile_id, name) values (p_profile_id, trim(p_display_name));
  elsif p_role = 'teacher' then
    update public.teachers set name = trim(p_display_name) where profile_id = p_profile_id;
  end if;

  insert into public.account_change_logs(changed_by, target_profile_id, action, details)
  values (auth.uid(), p_profile_id, 'account_updated', jsonb_build_object('previousRole', previous_role, 'role', p_role, 'previousActive', previous_active, 'isActive', p_is_active));
end
$$;

create or replace function public.admin_link_student_account(p_profile_id uuid, p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 학생 계정을 연결할 수 있습니다.'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id and p.role = 'student') then raise exception '학생 역할 계정을 선택해 주세요.'; end if;
  if p_student_id is not null and exists (select 1 from public.students s where s.id = p_student_id and s.profile_id is not null and s.profile_id <> p_profile_id) then raise exception '이미 다른 계정과 연결된 학생입니다.'; end if;
  update public.students set profile_id = null where profile_id = p_profile_id;
  if p_student_id is not null then
    update public.students set profile_id = p_profile_id where id = p_student_id;
    if not found then raise exception '학생을 찾을 수 없습니다.'; end if;
  end if;
  insert into public.account_change_logs(changed_by, target_profile_id, action, details)
  values (auth.uid(), p_profile_id, 'student_link_changed', jsonb_build_object('studentId', p_student_id));
end
$$;

create or replace function public.admin_set_guardian_children(p_profile_id uuid, p_child_ids uuid[], p_name text, p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare guardian_record_id uuid; child_id uuid;
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 학부모 계정을 연결할 수 있습니다.'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_profile_id and p.role = 'guardian') then raise exception '학부모 역할 계정을 선택해 주세요.'; end if;
  if nullif(trim(p_name), '') is null or nullif(trim(p_phone), '') is null then raise exception '학부모 이름과 연락처를 입력해 주세요.'; end if;
  select id into guardian_record_id from public.guardians where profile_id = p_profile_id;
  if guardian_record_id is null then
    insert into public.guardians(profile_id, name, phone) values (p_profile_id, trim(p_name), trim(p_phone)) returning id into guardian_record_id;
  else
    update public.guardians set name = trim(p_name), phone = trim(p_phone) where id = guardian_record_id;
  end if;
  delete from public.student_guardians where guardian_id = guardian_record_id;
  foreach child_id in array coalesce(p_child_ids, array[]::uuid[]) loop
    if not exists (select 1 from public.students s where s.id = child_id) then raise exception '연결할 학생을 찾을 수 없습니다.'; end if;
    insert into public.student_guardians(student_id, guardian_id, relationship, is_primary) values (child_id, guardian_record_id, '보호자', true);
  end loop;
  insert into public.account_change_logs(changed_by, target_profile_id, action, details)
  values (auth.uid(), p_profile_id, 'guardian_children_changed', jsonb_build_object('childIds', coalesce(p_child_ids, array[]::uuid[])));
end
$$;

create or replace function public.admin_save_account_settings(
  p_profile_id uuid,
  p_display_name text,
  p_phone text,
  p_role public.user_role,
  p_is_active boolean,
  p_student_id uuid,
  p_child_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 계정을 변경할 수 있습니다.'; end if;
  perform public.admin_update_account(p_profile_id, p_display_name, p_phone, p_role, p_is_active);
  if p_role = 'student' then
    perform public.admin_link_student_account(p_profile_id, p_student_id);
  elsif p_role = 'guardian' then
    perform public.admin_set_guardian_children(p_profile_id, p_child_ids, p_display_name, p_phone);
  end if;
end
$$;

revoke all on function public.admin_account_board() from public;
revoke all on function public.admin_update_account(uuid, text, text, public.user_role, boolean) from public;
revoke all on function public.admin_link_student_account(uuid, uuid) from public;
revoke all on function public.admin_set_guardian_children(uuid, uuid[], text, text) from public;
revoke all on function public.admin_save_account_settings(uuid, text, text, public.user_role, boolean, uuid, uuid[]) from public;
grant execute on function public.admin_account_board() to authenticated;
grant execute on function public.admin_update_account(uuid, text, text, public.user_role, boolean) to authenticated;
grant execute on function public.admin_link_student_account(uuid, uuid) to authenticated;
grant execute on function public.admin_set_guardian_children(uuid, uuid[], text, text) to authenticated;
grant execute on function public.admin_save_account_settings(uuid, text, text, public.user_role, boolean, uuid, uuid[]) to authenticated;
