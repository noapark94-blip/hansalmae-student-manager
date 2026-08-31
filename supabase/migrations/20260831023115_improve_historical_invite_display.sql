-- 과거 초대 기록에 수신자명이 없으면 실제 가입 계정의 표시 이름을 사용합니다.

create or replace function public.admin_account_invite_sms_board()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.current_user_role()='admin' then jsonb_build_object(
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.classes c where c.active),'[]'::jsonb),
    'grades',coalesce((select jsonb_agg(x.grade order by x.grade) from (select distinct s.grade from public.students s where s.status in ('active','재원') and nullif(trim(s.grade),'') is not null) x),'[]'::jsonb),
    'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct s.school from public.students s where s.status in ('active','재원') and nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,
        'classIds',coalesce(scope.class_ids,'[]'::jsonb),'classNames',coalesce(scope.class_names,'[]'::jsonb),
        'hasStudentAccount',s.profile_id is not null,
        'hasStudentPhone',nullif(regexp_replace(coalesce(s.phone,''),'\D','','g'),'') is not null,
        'guardianName',g.name,'guardianId',g.id,
        'hasGuardianAccount',g.profile_id is not null,
        'hasGuardianPhone',nullif(regexp_replace(coalesce(g.phone,''),'\D','','g'),'') is not null
      ) order by s.name)
      from public.students s
      left join lateral (
        select guardian.id,guardian.name,guardian.phone,guardian.profile_id
        from public.student_guardians sg join public.guardians guardian on guardian.id=sg.guardian_id
        where sg.student_id=s.id order by sg.is_primary desc,guardian.created_at limit 1
      ) g on true
      left join lateral (
        select jsonb_agg(c.id order by c.name) class_ids,jsonb_agg(c.name order by c.name) class_names
        from public.enrollments e join public.classes c on c.id=e.class_id
        where e.student_id=s.id and e.status='active' and c.active
      ) scope on true
      where s.status in ('active','재원')
    ),'[]'::jsonb),
    'invites',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'role',i.role,'studentId',i.student_id,
        'targetName',coalesce(i.recipient_name,used_profile.display_name,s.name,case i.role when 'teacher' then '선생님' else '초대 대상' end),
        'studentName',s.name,'maskedPhone',case when nullif(regexp_replace(coalesce(i.recipient_phone,''),'\D','','g'),'') is null then null else left(regexp_replace(i.recipient_phone,'\D','','g'),3)||'-****-'||right(regexp_replace(i.recipient_phone,'\D','','g'),4) end,
        'codeHint',i.code_hint,'createdAt',i.created_at,'expiresAt',i.expires_at,
        'smsSentAt',i.sms_sent_at,'smsAttempts',i.sms_attempts,'smsLastError',i.sms_last_error,
        'usedAt',i.used_at,'revokedAt',i.revoked_at,
        'status',case when i.used_at is not null then 'joined' when i.sms_sent_at is not null then 'sent' when i.sms_last_error is not null then 'failed' else 'unsent' end
      ) order by i.created_at desc)
      from (select * from public.account_invites order by created_at desc limit 300) i
      left join public.students s on s.id=i.student_id
      left join public.profiles used_profile on used_profile.id=i.used_by
      where i.role in ('student','guardian','teacher') and (i.revoked_at is null or i.used_at is not null)
    ),'[]'::jsonb)
  ) else null end
$$;

revoke all on function public.admin_account_invite_sms_board() from public;
grant execute on function public.admin_account_invite_sms_board() to authenticated;
