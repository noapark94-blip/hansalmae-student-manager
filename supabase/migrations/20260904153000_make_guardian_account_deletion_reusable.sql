-- Preserve guardian contact data when an auth account is deleted, while making
-- the same guardian row reusable for a later invitation signup.

create or replace function public.consolidate_guardian_contact(p_guardian_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target public.guardians%rowtype;
  duplicate record;
begin
  select * into target from public.guardians where id = p_guardian_id for update;
  if target.id is null then return null; end if;
  if length(regexp_replace(coalesce(target.phone,''),'\D','','g')) < 10 then return target.id; end if;

  for duplicate in
    select g.id
    from public.guardians g
    where g.id <> target.id
      and g.profile_id is null
      and regexp_replace(coalesce(g.phone,''),'\D','','g') = regexp_replace(target.phone,'\D','','g')
    order by g.created_at
    for update
  loop
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary)
    select sg.student_id,target.id,coalesce(sg.relationship,'보호자'),sg.is_primary
    from public.student_guardians sg where sg.guardian_id = duplicate.id
    on conflict(student_id,guardian_id) do update set
      relationship = coalesce(public.student_guardians.relationship,excluded.relationship),
      is_primary = public.student_guardians.is_primary or excluded.is_primary;
    delete from public.guardians where id = duplicate.id;
  end loop;
  return target.id;
end $$;

create or replace function public.admin_prepare_guardian_account_deletion(p_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare guardian_record_id uuid;
begin
  select g.id into guardian_record_id
  from public.guardians g where g.profile_id = p_profile_id
  order by g.created_at limit 1 for update;
  if guardian_record_id is not null then
    perform public.consolidate_guardian_contact(guardian_record_id);
  end if;
  return guardian_record_id;
end $$;

create or replace function public.claim_account_invite(p_code_hash bytea,p_profile_id uuid,p_display_name text,p_phone text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare invitation public.account_invites%rowtype; guardian_record_id uuid; effective_name text; target record; v_names jsonb;
begin
  select * into invitation from public.account_invites where code_hash=p_code_hash for update;
  if invitation.id is null or invitation.used_at is not null or invitation.revoked_at is not null or invitation.expires_at<=now() then raise exception '초대코드가 올바르지 않거나 만료되었습니다.'; end if;
  if invitation.role='student' then
    select name into effective_name from public.students where id=invitation.student_id;
    if effective_name is null then raise exception '연결할 학생 정보를 찾지 못했습니다.'; end if;
  else effective_name:=nullif(trim(p_display_name),''); end if;
  if effective_name is null then raise exception '이름을 입력해 주세요.'; end if;
  if invitation.role='guardian' and nullif(trim(p_phone),'') is null then raise exception '학부모 연락처를 입력해 주세요.'; end if;
  if invitation.role='student' and exists(select 1 from public.students where id=invitation.student_id and profile_id is not null) then raise exception '이미 계정이 연결된 학생입니다.'; end if;
  update public.profiles set role=invitation.role,display_name=effective_name,phone=nullif(trim(p_phone),''),is_active=true where id=p_profile_id;
  if not found then insert into public.profiles(id,role,display_name,phone,is_active) values(p_profile_id,invitation.role,effective_name,nullif(trim(p_phone),''),true); end if;
  if invitation.role='student' then
    update public.students set profile_id=p_profile_id,phone=coalesce(nullif(trim(p_phone),''),phone) where id=invitation.student_id;
  elsif invitation.role='guardian' then
    select g.id into guardian_record_id
    from public.account_invite_students ais
    join public.student_guardians sg on sg.student_id=ais.student_id
    join public.guardians g on g.id=sg.guardian_id
    where ais.invite_id=invitation.id and g.profile_id is null
      and regexp_replace(coalesce(g.phone,''),'\D','','g')=regexp_replace(trim(p_phone),'\D','','g')
    order by ais.is_primary desc,sg.is_primary desc,g.created_at
    limit 1 for update of g;
    if guardian_record_id is null then
      insert into public.guardians(profile_id,name,phone) values(p_profile_id,effective_name,trim(p_phone)) returning id into guardian_record_id;
    else
      update public.guardians set profile_id=p_profile_id,name=effective_name,phone=trim(p_phone) where id=guardian_record_id;
    end if;
    for target in select ais.student_id,ais.is_primary from public.account_invite_students ais where ais.invite_id=invitation.id order by ais.is_primary desc,ais.created_at loop
      insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(target.student_id,guardian_record_id,'보호자',target.is_primary)
      on conflict(student_id,guardian_id) do update set relationship='보호자',is_primary=excluded.is_primary;
    end loop;
    if not found then
      insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(invitation.student_id,guardian_record_id,'보호자',true)
      on conflict(student_id,guardian_id) do update set relationship='보호자',is_primary=true;
    end if;
    perform public.consolidate_guardian_contact(guardian_record_id);
  else
    insert into public.teachers(profile_id,name) values(p_profile_id,effective_name);
  end if;
  update public.account_invites set used_at=now(),used_by=p_profile_id where id=invitation.id;
  select coalesce(jsonb_agg(s.name order by ais.is_primary desc,ais.created_at),'[]'::jsonb) into v_names from public.account_invite_students ais join public.students s on s.id=ais.student_id where ais.invite_id=invitation.id;
  return jsonb_build_object('role',invitation.role,'targetName',effective_name,'targetNames',v_names);
end $$;

revoke all on function public.consolidate_guardian_contact(uuid),public.admin_prepare_guardian_account_deletion(uuid),public.claim_account_invite(bytea,uuid,text,text) from public,anon,authenticated;
grant execute on function public.consolidate_guardian_contact(uuid),public.admin_prepare_guardian_account_deletion(uuid),public.claim_account_invite(bytea,uuid,text,text) to service_role;
notify pgrst,'reload schema';
