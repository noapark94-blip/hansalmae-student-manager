-- 한 학부모 초대코드에 여러 자녀를 안전하게 연결합니다.

create table public.account_invite_students (
  invite_id uuid not null references public.account_invites(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key(invite_id,student_id)
);
create index account_invite_students_student_idx on public.account_invite_students(student_id,invite_id);
alter table public.account_invite_students enable row level security;
revoke all on table public.account_invite_students from public,anon,authenticated;

insert into public.account_invite_students(invite_id,student_id,is_primary)
select id,student_id,true from public.account_invites where student_id is not null
on conflict(invite_id,student_id) do nothing;

create or replace function public.sync_account_invite_primary_student()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.student_id is not null then
    insert into public.account_invite_students(invite_id,student_id,is_primary)
    values(new.id,new.student_id,true) on conflict(invite_id,student_id) do nothing;
  end if;
  return new;
end $$;
create trigger account_invite_primary_student_sync
after insert on public.account_invites for each row execute function public.sync_account_invite_primary_student();
revoke all on function public.sync_account_invite_primary_student() from public,anon,authenticated;

create or replace function public.admin_set_guardian_invite_students(p_invite_id uuid,p_student_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_invite public.account_invites%rowtype; v_ids uuid[]; v_count integer; v_names text;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 연결 자녀를 지정할 수 있습니다.'; end if;
  select * into v_invite from public.account_invites where id=p_invite_id and role='guardian' and used_at is null and revoked_at is null and expires_at>now() for update;
  if not found then raise exception '사용 가능한 학부모 초대코드를 찾지 못했습니다.'; end if;
  select array_agg(id order by ord),count(*) into v_ids,v_count
  from (select distinct on (student_id) student_id as id,ord from unnest(coalesce(p_student_ids,array[]::uuid[])) with ordinality x(student_id,ord) order by student_id,ord) x;
  if coalesce(v_count,0)<1 or coalesce(v_count,0)>10 then raise exception '연결할 자녀를 1명 이상 10명 이하로 선택해 주세요.'; end if;
  if not v_invite.student_id=any(v_ids) then raise exception '대표 학생이 연결 자녀 목록에 포함되어야 합니다.'; end if;
  if (select count(*) from public.students s where s.id=any(v_ids) and s.status in ('active','재원'))<>v_count then raise exception '재원 중인 학생만 연결할 수 있습니다.'; end if;
  delete from public.account_invite_students where invite_id=p_invite_id;
  insert into public.account_invite_students(invite_id,student_id,is_primary)
  select p_invite_id,id,id=v_invite.student_id from unnest(v_ids) id;
  select string_agg(s.name,', ' order by x.ord) into v_names from unnest(v_ids) with ordinality x(id,ord) join public.students s on s.id=x.id;
  return jsonb_build_object('inviteId',p_invite_id,'studentIds',v_ids,'targetName',v_names);
end $$;

create or replace function public.admin_issue_guardian_account_invite(p_student_ids uuid[],p_valid_days integer default 14)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_ids uuid[]; v_primary uuid; v_count integer; v_code text:=''; v_chars constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_i integer; v_invite_id uuid; v_names text;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 초대코드를 발급할 수 있습니다.'; end if;
  if p_valid_days<1 or p_valid_days>30 then raise exception '유효기간은 1~30일로 설정해 주세요.'; end if;
  select array_agg(id order by ord),count(*) into v_ids,v_count
  from (select distinct on (student_id) student_id as id,ord from unnest(coalesce(p_student_ids,array[]::uuid[])) with ordinality x(student_id,ord) order by student_id,ord) x;
  if coalesce(v_count,0)<1 or coalesce(v_count,0)>10 then raise exception '연결할 자녀를 1명 이상 10명 이하로 선택해 주세요.'; end if;
  if (select count(*) from public.students s where s.id=any(v_ids) and s.status in ('active','재원'))<>v_count then raise exception '재원 중인 학생만 연결할 수 있습니다.'; end if;
  v_primary:=v_ids[1];
  update public.account_invites i set revoked_at=now()
  where i.role='guardian' and i.used_at is null and i.revoked_at is null and i.expires_at>now()
    and exists(select 1 from public.account_invite_students ais where ais.invite_id=i.id and ais.student_id=any(v_ids));
  loop
    v_code:=''; for v_i in 1..8 loop v_code:=v_code||substr(v_chars,1+floor(random()*length(v_chars))::integer,1); end loop;
    exit when not exists(select 1 from public.account_invites where code_hash=digest(v_code,'sha256'));
  end loop;
  insert into public.account_invites(code_hash,code_hint,role,student_id,created_by,expires_at)
  values(digest(v_code,'sha256'),right(v_code,4),'guardian',v_primary,auth.uid(),now()+make_interval(days=>p_valid_days))
  returning id into v_invite_id;
  perform public.admin_set_guardian_invite_students(v_invite_id,v_ids);
  select string_agg(s.name,', ' order by x.ord) into v_names from unnest(v_ids) with ordinality x(id,ord) join public.students s on s.id=x.id;
  return jsonb_build_object('id',v_invite_id,'code',v_code,'role','guardian','targetName',v_names,'studentIds',v_ids,'expiresAt',now()+make_interval(days=>p_valid_days));
end $$;

create or replace function public.check_account_invite(p_code_hash bytea)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare invitation public.account_invites%rowtype; v_names jsonb;
begin
  select * into invitation from public.account_invites where code_hash=p_code_hash;
  if invitation.id is null or invitation.used_at is not null or invitation.revoked_at is not null or invitation.expires_at<=now() then return null; end if;
  select coalesce(jsonb_agg(s.name order by ais.is_primary desc,ais.created_at),'[]'::jsonb) into v_names
  from public.account_invite_students ais join public.students s on s.id=ais.student_id where ais.invite_id=invitation.id;
  return jsonb_build_object('id',invitation.id,'role',invitation.role,
    'targetName',case when invitation.role in ('student','guardian') then (select string_agg(value,', ') from jsonb_array_elements_text(v_names)) else case invitation.role when 'assistant' then '조교 계정' when 'manager' then '실장님 계정' else '선생님 계정' end end,
    'targetNames',v_names);
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
    insert into public.guardians(profile_id,name,phone) values(p_profile_id,effective_name,trim(p_phone)) returning id into guardian_record_id;
    for target in select ais.student_id,ais.is_primary from public.account_invite_students ais where ais.invite_id=invitation.id order by ais.is_primary desc,ais.created_at loop
      insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(target.student_id,guardian_record_id,'보호자',target.is_primary);
    end loop;
    if not found then insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(invitation.student_id,guardian_record_id,'보호자',true); end if;
  else
    insert into public.teachers(profile_id,name) values(p_profile_id,effective_name);
  end if;
  update public.account_invites set used_at=now(),used_by=p_profile_id where id=invitation.id;
  select coalesce(jsonb_agg(s.name order by ais.is_primary desc,ais.created_at),'[]'::jsonb) into v_names from public.account_invite_students ais join public.students s on s.id=ais.student_id where ais.invite_id=invitation.id;
  return jsonb_build_object('role',invitation.role,'targetName',effective_name,'targetNames',v_names);
end $$;

create or replace function public.admin_account_invite_board()
returns jsonb language plpgsql stable security definer set search_path=public,extensions as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 초대코드를 확인할 수 있습니다.'; end if;
  return jsonb_build_object(
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'hasAccount',s.profile_id is not null,
      'guardianName',g.name,'siblingStudentIds',coalesce(g.sibling_ids,'[]'::jsonb)
    ) order by s.name) from public.students s
    left join lateral (
      select guardian.name,(select jsonb_agg(distinct sibling.student_id) from public.student_guardians sibling join public.guardians sibling_g on sibling_g.id=sibling.guardian_id where regexp_replace(coalesce(sibling_g.phone,''),'\D','','g')=regexp_replace(coalesce(guardian.phone,''),'\D','','g') and length(regexp_replace(coalesce(guardian.phone,''),'\D','','g'))>=10 and sibling.student_id<>s.id) sibling_ids
      from public.student_guardians sg join public.guardians guardian on guardian.id=sg.guardian_id where sg.student_id=s.id order by sg.is_primary desc,guardian.created_at limit 1
    ) g on true where s.status in ('active','재원')),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'codeHint',i.code_hint,'role',i.role,'studentId',i.student_id,
      'targetName',coalesce(children.names,case i.role when 'assistant' then '새 조교' when 'manager' then '새 실장님' else '새 선생님' end),
      'expiresAt',i.expires_at,'createdAt',i.created_at,'usedAt',i.used_at,'revokedAt',i.revoked_at,
      'status',case when i.used_at is not null then 'used' when i.revoked_at is not null then 'revoked' when i.expires_at<=now() then 'expired' else 'active' end
    ) order by i.created_at desc) from (select * from public.account_invites order by created_at desc limit 50) i
    left join lateral (select string_agg(s.name,', ' order by ais.is_primary desc,ais.created_at) names from public.account_invite_students ais join public.students s on s.id=ais.student_id where ais.invite_id=i.id) children on true),'[]'::jsonb)
  );
end $$;

create or replace function public.admin_account_invite_sms_board()
returns jsonb language sql stable security definer set search_path=public,extensions as $$
  select case when public.current_user_role()='admin' then jsonb_build_object(
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.classes c where c.active),'[]'::jsonb),
    'grades',coalesce((select jsonb_agg(x.grade order by x.grade) from (select distinct s.grade from public.students s where s.status in ('active','재원') and nullif(trim(s.grade),'') is not null) x),'[]'::jsonb),
    'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct s.school from public.students s where s.status in ('active','재원') and nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'classIds',coalesce(scope.class_ids,'[]'::jsonb),'classNames',coalesce(scope.class_names,'[]'::jsonb),
      'hasStudentAccount',s.profile_id is not null,'hasStudentPhone',nullif(regexp_replace(coalesce(s.phone,''),'\D','','g'),'') is not null,
      'guardianName',g.name,'guardianId',g.id,'guardianFamilyKey',g.family_key,'hasGuardianAccount',g.profile_id is not null,
      'hasGuardianPhone',coalesce(length(g.phone_digits)>=10,false)
    ) order by s.name) from public.students s
    left join lateral (select guardian.id,guardian.name,guardian.profile_id,regexp_replace(coalesce(guardian.phone,''),'\D','','g') phone_digits,case when length(regexp_replace(coalesce(guardian.phone,''),'\D','','g'))>=10 then encode(digest(regexp_replace(guardian.phone,'\D','','g'),'sha256'),'hex') end family_key from public.student_guardians sg join public.guardians guardian on guardian.id=sg.guardian_id where sg.student_id=s.id order by sg.is_primary desc,guardian.created_at limit 1) g on true
    left join lateral (select jsonb_agg(c.id order by c.name) class_ids,jsonb_agg(c.name order by c.name) class_names from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=s.id and e.status='active' and c.active) scope on true
    where s.status in ('active','재원')),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(jsonb_build_object(
      'id',i.id,'role',i.role,'studentId',i.student_id,'studentIds',coalesce(children.ids,'[]'::jsonb),'targetName',coalesce(i.recipient_name,used_profile.display_name,children.names,case i.role when 'teacher' then '선생님' else '초대 대상' end),
      'studentName',children.names,'maskedPhone',case when nullif(regexp_replace(coalesce(i.recipient_phone,''),'\D','','g'),'') is null then null else left(regexp_replace(i.recipient_phone,'\D','','g'),3)||'-****-'||right(regexp_replace(i.recipient_phone,'\D','','g'),4) end,
      'codeHint',i.code_hint,'createdAt',i.created_at,'expiresAt',i.expires_at,'smsSentAt',i.sms_sent_at,'smsAttempts',i.sms_attempts,'smsLastError',i.sms_last_error,
      'usedAt',i.used_at,'revokedAt',i.revoked_at,'status',case when i.used_at is not null then 'joined' when i.sms_sent_at is not null then 'sent' when i.sms_last_error is not null then 'failed' else 'unsent' end
    ) order by i.created_at desc) from (select * from public.account_invites order by created_at desc limit 300) i
    left join public.profiles used_profile on used_profile.id=i.used_by
    left join lateral (select string_agg(s.name,', ' order by ais.is_primary desc,ais.created_at) names,jsonb_agg(s.id order by ais.is_primary desc,ais.created_at) ids from public.account_invite_students ais join public.students s on s.id=ais.student_id where ais.invite_id=i.id) children on true
    where i.role in ('student','guardian','teacher') and (i.revoked_at is null or i.used_at is not null)),'[]'::jsonb)
  ) else null end
$$;

revoke all on function public.admin_set_guardian_invite_students(uuid,uuid[]),public.admin_issue_guardian_account_invite(uuid[],integer) from public,anon;
grant execute on function public.admin_set_guardian_invite_students(uuid,uuid[]),public.admin_issue_guardian_account_invite(uuid[],integer) to authenticated;
revoke all on function public.check_account_invite(bytea),public.claim_account_invite(bytea,uuid,text,text) from public,anon,authenticated;
grant execute on function public.check_account_invite(bytea),public.claim_account_invite(bytea,uuid,text,text) to service_role;
revoke all on function public.admin_account_invite_board(),public.admin_account_invite_sms_board() from public,anon;
grant execute on function public.admin_account_invite_board(),public.admin_account_invite_sms_board() to authenticated;
notify pgrst,'reload schema';
