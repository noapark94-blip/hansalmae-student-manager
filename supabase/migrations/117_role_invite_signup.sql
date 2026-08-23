-- 역할별 일회용 초대코드와 안전한 가입 연결 흐름
create table public.account_invites (
  id uuid primary key default gen_random_uuid(),
  code_hash bytea not null unique,
  code_hint text not null,
  role public.user_role not null check (role in ('teacher','student','guardian')),
  student_id uuid references public.students(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete restrict,
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check ((role in ('student','guardian') and student_id is not null) or (role='teacher' and student_id is null))
);

alter table public.account_invites enable row level security;
revoke all on table public.account_invites from anon, authenticated;

create or replace function public.admin_issue_account_invite(
  p_role public.user_role,
  p_student_id uuid default null,
  p_valid_days integer default 14
)
returns jsonb
language plpgsql
security definer
set search_path=public, extensions
as $$
declare
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  plain_code text := '';
  invite_id uuid;
  target_name text;
  i integer;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 초대코드를 발급할 수 있습니다.'; end if;
  if p_role not in ('teacher','student','guardian') then raise exception '학생, 학부모 또는 선생님 역할을 선택해 주세요.'; end if;
  if p_valid_days<1 or p_valid_days>30 then raise exception '유효기간은 1~30일로 설정해 주세요.'; end if;

  if p_role in ('student','guardian') then
    select name into target_name from public.students where id=p_student_id and status in ('active','재원');
    if target_name is null then raise exception '연결할 재원 학생을 선택해 주세요.'; end if;
    if p_role='student' and exists(select 1 from public.students where id=p_student_id and profile_id is not null) then
      raise exception '이미 로그인 계정이 연결된 학생입니다.';
    end if;
    update public.account_invites set revoked_at=now()
      where role=p_role and student_id=p_student_id and used_at is null and revoked_at is null and expires_at>now();
  else
    target_name := '새 선생님';
  end if;

  loop
    plain_code := '';
    for i in 1..8 loop
      plain_code := plain_code || substr(chars, 1+floor(random()*length(chars))::integer, 1);
    end loop;
    exit when not exists(select 1 from public.account_invites where code_hash=digest(plain_code,'sha256'));
  end loop;

  insert into public.account_invites(code_hash,code_hint,role,student_id,created_by,expires_at)
  values(digest(plain_code,'sha256'),right(plain_code,4),p_role,case when p_role='teacher' then null else p_student_id end,auth.uid(),now()+make_interval(days=>p_valid_days))
  returning id into invite_id;

  return jsonb_build_object('id',invite_id,'code',plain_code,'role',p_role,'targetName',target_name,'expiresAt',now()+make_interval(days=>p_valid_days));
end
$$;

create or replace function public.admin_account_invite_board()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 초대코드를 확인할 수 있습니다.'; end if;
  return jsonb_build_object(
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'hasAccount',s.profile_id is not null) order by s.name) from public.students s where s.status in ('active','재원')),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'codeHint',i.code_hint,'role',i.role,'studentId',i.student_id,'targetName',coalesce(s.name,'새 선생님'),
      'expiresAt',i.expires_at,'createdAt',i.created_at,'usedAt',i.used_at,'revokedAt',i.revoked_at,
      'status',case when i.used_at is not null then 'used' when i.revoked_at is not null then 'revoked' when i.expires_at<=now() then 'expired' else 'active' end
    ) order by i.created_at desc) from (select * from public.account_invites order by created_at desc limit 50) i left join public.students s on s.id=i.student_id),'[]'::jsonb)
  );
end
$$;

create or replace function public.admin_revoke_account_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 초대코드를 폐기할 수 있습니다.'; end if;
  update public.account_invites set revoked_at=now() where id=p_invite_id and used_at is null and revoked_at is null;
  if not found then raise exception '사용 가능한 초대코드를 찾을 수 없습니다.'; end if;
end
$$;

create or replace function public.claim_account_invite(
  p_code_hash bytea,
  p_profile_id uuid,
  p_display_name text,
  p_phone text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  invitation public.account_invites%rowtype;
  guardian_record_id uuid;
begin
  select * into invitation from public.account_invites where code_hash=p_code_hash for update;
  if invitation.id is null or invitation.used_at is not null or invitation.revoked_at is not null or invitation.expires_at<=now() then
    raise exception '초대코드가 올바르지 않거나 만료되었습니다.';
  end if;
  if nullif(trim(p_display_name),'') is null then raise exception '이름을 입력해 주세요.'; end if;
  if invitation.role='guardian' and nullif(trim(p_phone),'') is null then raise exception '학부모 연락처를 입력해 주세요.'; end if;
  if invitation.role='student' and exists(select 1 from public.students where id=invitation.student_id and profile_id is not null) then
    raise exception '이미 계정이 연결된 학생입니다.';
  end if;

  update public.profiles set role=invitation.role,display_name=trim(p_display_name),phone=nullif(trim(p_phone),''),is_active=true where id=p_profile_id;
  if not found then
    insert into public.profiles(id,role,display_name,phone,is_active) values(p_profile_id,invitation.role,trim(p_display_name),nullif(trim(p_phone),''),true);
  end if;

  if invitation.role='student' then
    update public.students set profile_id=p_profile_id,phone=coalesce(nullif(trim(p_phone),''),phone) where id=invitation.student_id;
  elsif invitation.role='guardian' then
    insert into public.guardians(profile_id,name,phone) values(p_profile_id,trim(p_display_name),trim(p_phone))
      returning id into guardian_record_id;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary)
      values(invitation.student_id,guardian_record_id,'보호자',true);
  else
    insert into public.teachers(profile_id,name) values(p_profile_id,trim(p_display_name));
  end if;

  update public.account_invites set used_at=now(),used_by=p_profile_id where id=invitation.id;
  return jsonb_build_object('role',invitation.role,'targetName',coalesce((select name from public.students where id=invitation.student_id),trim(p_display_name)));
end
$$;

revoke all on function public.admin_issue_account_invite(public.user_role,uuid,integer) from public;
revoke all on function public.admin_account_invite_board() from public;
revoke all on function public.admin_revoke_account_invite(uuid) from public;
revoke all on function public.claim_account_invite(bytea,uuid,text,text) from public;
grant execute on function public.admin_issue_account_invite(public.user_role,uuid,integer) to authenticated;
grant execute on function public.admin_account_invite_board() to authenticated;
grant execute on function public.admin_revoke_account_invite(uuid) to authenticated;
grant execute on function public.claim_account_invite(bytea,uuid,text,text) to service_role;
