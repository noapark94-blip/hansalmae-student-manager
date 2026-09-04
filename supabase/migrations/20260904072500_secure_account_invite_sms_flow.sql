create or replace function public.admin_prepare_account_invite_sms(
  p_action text,
  p_invite_id uuid default null,
  p_code text default null,
  p_role public.user_role default null,
  p_student_id uuid default null,
  p_recipient_name text default null,
  p_recipient_phone text default null
) returns jsonb
language plpgsql
security definer
set search_path = 'public', 'extensions'
as $$
declare
  v_invite public.account_invites%rowtype;
  v_previous public.account_invites%rowtype;
  v_student public.students%rowtype;
  v_guardian public.guardians%rowtype;
  v_role public.user_role;
  v_student_id uuid;
  v_name text;
  v_phone text;
  v_code text;
  v_chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_i integer;
begin
  if public.current_user_role() <> 'admin' then
    raise exception '관리자만 초대 문자를 보낼 수 있습니다.';
  end if;

  if p_action = 'send' then
    select * into v_invite from public.account_invites
    where id = p_invite_id and used_at is null and revoked_at is null and expires_at > now()
    for update;
    if not found or digest(upper(regexp_replace(coalesce(p_code,''),'[^A-Z0-9]','','g')), 'sha256') <> v_invite.code_hash then
      raise exception '사용 가능한 초대코드를 찾을 수 없습니다.';
    end if;
    v_code := upper(regexp_replace(p_code,'[^A-Z0-9]','','g'));
    v_role := v_invite.role;
    v_student_id := v_invite.student_id;
  else
    if p_action = 'resend' then
      select * into v_previous from public.account_invites where id = p_invite_id and used_at is null for update;
      if not found then raise exception '재발송할 초대 내역을 찾지 못했습니다.'; end if;
      v_role := v_previous.role;
      v_student_id := v_previous.student_id;
      p_recipient_name := coalesce(p_recipient_name, v_previous.recipient_name);
      p_recipient_phone := coalesce(p_recipient_phone, v_previous.recipient_phone);
      update public.account_invites set revoked_at = now() where id = v_previous.id;
    else
      v_role := p_role;
      v_student_id := p_student_id;
    end if;

    if v_role not in ('student','guardian','teacher') then raise exception '초대 대상을 확인해 주세요.'; end if;

    if v_role in ('student','guardian') then
      select * into v_student from public.students where id = v_student_id and status in ('active','재원');
      if not found then raise exception '재원 학생을 선택해 주세요.'; end if;
      if v_role = 'student' then
        if v_student.profile_id is not null then raise exception '이미 학생 계정 가입을 완료했습니다.'; end if;
        v_name := v_student.name;
        v_phone := regexp_replace(coalesce(v_student.phone,''),'\D','','g');
      else
        select g.* into v_guardian
        from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
        where sg.student_id = v_student.id
        order by sg.is_primary desc, g.created_at
        limit 1;
        if v_guardian.profile_id is not null then raise exception '이미 학부모 계정 가입을 완료했습니다.'; end if;
        v_name := coalesce(v_guardian.name, v_student.name || ' 학부모');
        v_phone := regexp_replace(coalesce(v_guardian.phone,''),'\D','','g');
      end if;
      update public.account_invites set revoked_at = now()
      where role = v_role and student_id = v_student_id and used_at is null and revoked_at is null;
    else
      v_name := trim(coalesce(p_recipient_name,''));
      v_phone := regexp_replace(coalesce(p_recipient_phone,''),'\D','','g');
      if v_name = '' then raise exception '선생님 이름을 입력해 주세요.'; end if;
    end if;

    if length(v_phone) < 10 then raise exception '발송할 휴대전화 번호를 확인해 주세요.'; end if;
    loop
      v_code := '';
      for v_i in 1..8 loop v_code := v_code || substr(v_chars, 1 + floor(random()*length(v_chars))::integer, 1); end loop;
      exit when not exists(select 1 from public.account_invites where code_hash = digest(v_code,'sha256'));
    end loop;
    insert into public.account_invites(code_hash,code_hint,role,student_id,created_by,expires_at,recipient_name,recipient_phone)
    values(digest(v_code,'sha256'),right(v_code,4),v_role,case when v_role='teacher' then null else v_student_id end,auth.uid(),now()+interval '14 days',v_name,v_phone)
    returning * into v_invite;
  end if;

  if v_role in ('student','guardian') then
    select * into v_student from public.students where id = v_student_id;
    if v_role = 'student' then
      v_name := coalesce(v_invite.recipient_name, v_student.name);
      v_phone := regexp_replace(coalesce(v_invite.recipient_phone,v_student.phone,''),'\D','','g');
    else
      select g.* into v_guardian from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
      where sg.student_id=v_student_id order by sg.is_primary desc,g.created_at limit 1;
      v_name := coalesce(v_invite.recipient_name,v_guardian.name,v_student.name||' 학부모');
      v_phone := regexp_replace(coalesce(v_invite.recipient_phone,v_guardian.phone,''),'\D','','g');
    end if;
  else
    v_name := coalesce(v_invite.recipient_name,p_recipient_name,'선생님');
    v_phone := regexp_replace(coalesce(v_invite.recipient_phone,p_recipient_phone,''),'\D','','g');
  end if;
  if length(v_phone) < 10 then raise exception '발송할 휴대전화 번호를 확인해 주세요.'; end if;

  update public.account_invites set recipient_name=v_name,recipient_phone=v_phone,sms_attempts=coalesce(sms_attempts,0)+1,sms_last_error=null where id=v_invite.id;
  return jsonb_build_object('inviteId',v_invite.id,'code',v_code,'role',v_role,'recipientName',v_name,'studentName',v_student.name,'recipientPhone',v_phone);
end;
$$;

create or replace function public.admin_finish_account_invite_sms(
  p_invite_id uuid,
  p_success boolean,
  p_error text default null,
  p_provider_message_id text default null
) returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 초대 문자를 처리할 수 있습니다.'; end if;
  update public.account_invites set
    sms_sent_at = case when p_success then now() else sms_sent_at end,
    sms_last_error = case when p_success then null else left(coalesce(p_error,'초대 문자를 발송하지 못했습니다.'),500) end,
    sms_provider_message_id = case when p_success then p_provider_message_id else sms_provider_message_id end
  where id=p_invite_id;
  return found;
end;
$$;

revoke all on function public.admin_prepare_account_invite_sms(text,uuid,text,public.user_role,uuid,text,text) from public;
grant execute on function public.admin_prepare_account_invite_sms(text,uuid,text,public.user_role,uuid,text,text) to authenticated;
revoke all on function public.admin_finish_account_invite_sms(uuid,boolean,text,text) from public;
grant execute on function public.admin_finish_account_invite_sms(uuid,boolean,text,text) to authenticated;
