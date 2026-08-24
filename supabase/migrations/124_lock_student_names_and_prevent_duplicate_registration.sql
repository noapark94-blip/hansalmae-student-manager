-- 학생 계정 이름은 기존 학생부 이름으로 고정하고, 동일 학생의 중복 등록을 방지합니다.

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
  effective_name text;
begin
  select * into invitation from public.account_invites where code_hash=p_code_hash for update;
  if invitation.id is null or invitation.used_at is not null or invitation.revoked_at is not null or invitation.expires_at<=now() then
    raise exception '초대코드가 올바르지 않거나 만료되었습니다.';
  end if;

  if invitation.role='student' then
    select name into effective_name from public.students where id=invitation.student_id;
    if effective_name is null then raise exception '연결할 학생 정보를 찾지 못했습니다.'; end if;
  else
    effective_name:=nullif(trim(p_display_name),'');
  end if;
  if effective_name is null then raise exception '이름을 입력해 주세요.'; end if;
  if invitation.role='guardian' and nullif(trim(p_phone),'') is null then raise exception '학부모 연락처를 입력해 주세요.'; end if;
  if invitation.role='student' and exists(select 1 from public.students where id=invitation.student_id and profile_id is not null) then
    raise exception '이미 계정이 연결된 학생입니다.';
  end if;

  update public.profiles set role=invitation.role,display_name=effective_name,phone=nullif(trim(p_phone),''),is_active=true where id=p_profile_id;
  if not found then
    insert into public.profiles(id,role,display_name,phone,is_active) values(p_profile_id,invitation.role,effective_name,nullif(trim(p_phone),''),true);
  end if;

  if invitation.role='student' then
    update public.students set profile_id=p_profile_id,phone=coalesce(nullif(trim(p_phone),''),phone) where id=invitation.student_id;
  elsif invitation.role='guardian' then
    insert into public.guardians(profile_id,name,phone) values(p_profile_id,effective_name,trim(p_phone)) returning id into guardian_record_id;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(invitation.student_id,guardian_record_id,'보호자',true);
  else
    insert into public.teachers(profile_id,name) values(p_profile_id,effective_name);
  end if;

  update public.account_invites set used_at=now(),used_by=p_profile_id where id=invitation.id;
  return jsonb_build_object('role',invitation.role,'targetName',effective_name);
end
$$;

revoke all on function public.claim_account_invite(bytea,uuid,text,text) from public;
grant execute on function public.claim_account_invite(bytea,uuid,text,text) to service_role;

create or replace function public.save_my_account(p_display_name text,p_phone text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  my_role public.user_role;
  effective_name text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  select role into my_role from public.profiles where id=auth.uid() and is_active;
  if my_role is null then raise exception '활성 계정을 찾을 수 없습니다.'; end if;
  if my_role='student' then
    select name into effective_name from public.students where profile_id=auth.uid();
    if effective_name is null then raise exception '연결된 학생 정보를 찾지 못했습니다.'; end if;
  else
    effective_name:=nullif(trim(p_display_name),'');
  end if;
  if effective_name is null then raise exception '표시 이름을 입력해 주세요.'; end if;
  if my_role='guardian' and nullif(trim(p_phone),'') is null then raise exception '학부모 연락처를 입력해 주세요.'; end if;

  update public.profiles set display_name=effective_name,phone=nullif(trim(p_phone),'') where id=auth.uid();
  update public.teachers set name=effective_name where profile_id=auth.uid();
  update public.students set phone=nullif(trim(p_phone),'') where profile_id=auth.uid();
  update public.guardians set name=effective_name,phone=trim(p_phone) where profile_id=auth.uid();
end
$$;

revoke all on function public.save_my_account(text,text) from public;
grant execute on function public.save_my_account(text,text) to authenticated;

create or replace function public.staff_register_student_with_guardian(
  p_name text,
  p_school text default null,
  p_grade text default null,
  p_phone text default null,
  p_status text default 'active',
  p_internal_note text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null
)
returns jsonb
language plpgsql
security invoker
set search_path=public
as $$
declare
  new_student public.students;
  new_guardian_id uuid;
begin
  if not public.is_staff() then raise exception 'staff access required'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'student name is required'; end if;

  if exists(
    select 1 from public.students s
    where lower(regexp_replace(trim(s.name),'[[:space:]]+','','g'))=lower(regexp_replace(trim(p_name),'[[:space:]]+','','g'))
      and coalesce(lower(regexp_replace(trim(s.school),'[[:space:]]+','','g')),'')=coalesce(lower(regexp_replace(trim(p_school),'[[:space:]]+','','g')),'')
      and coalesce(lower(regexp_replace(trim(s.grade),'[[:space:]]+','','g')),'')=coalesce(lower(regexp_replace(trim(p_grade),'[[:space:]]+','','g')),'')
  ) then
    raise exception '같은 이름·학교·학년의 학생이 이미 등록되어 있습니다.';
  end if;

  insert into public.students(name,school,grade,phone,status,internal_note)
  values(trim(p_name),nullif(trim(p_school),''),nullif(trim(p_grade),''),nullif(trim(p_phone),''),coalesce(nullif(trim(p_status),''),'active'),nullif(trim(p_internal_note),''))
  returning * into new_student;

  if nullif(trim(p_guardian_phone),'') is not null then
    insert into public.guardians(name,phone) values(coalesce(nullif(trim(p_guardian_name),''),trim(p_name)||' 보호자'),trim(p_guardian_phone)) returning id into new_guardian_id;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(new_student.id,new_guardian_id,'학부모',true);
  end if;

  return jsonb_build_object('id',new_student.id,'name',new_student.name,'school',new_student.school,'grade',new_student.grade,'status',new_student.status);
end
$$;

revoke all on function public.staff_register_student_with_guardian(text,text,text,text,text,text,text,text) from public;
grant execute on function public.staff_register_student_with_guardian(text,text,text,text,text,text,text,text) to authenticated;
