-- 기능 적용 이후 등록된 학생만 신규 초대 대상으로 표시합니다.

create or replace function public.admin_account_invite_sms_board()
returns jsonb language sql stable security definer set search_path=public,extensions as $$
  select case when public.current_user_role()='admin' then jsonb_build_object(
    'newStudentTrackingStartedAt','2026-09-07T00:00:00+09:00',
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.classes c where c.active),'[]'::jsonb),
    'grades',coalesce((select jsonb_agg(x.grade order by x.grade) from (select distinct s.grade from public.students s where s.status in ('active','재원') and nullif(trim(s.grade),'') is not null) x),'[]'::jsonb),
    'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct s.school from public.students s where s.status in ('active','재원') and nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'createdAt',s.created_at,
      'isNew',s.created_at >= timestamptz '2026-09-07 00:00:00+09' and not coalesce(g.has_account,false),
      'classIds',coalesce(scope.class_ids,'[]'::jsonb),'classNames',coalesce(scope.class_names,'[]'::jsonb),
      'hasStudentAccount',s.profile_id is not null,'hasStudentPhone',nullif(regexp_replace(coalesce(s.phone,''),'\D','','g'),'') is not null,
      'guardianName',g.name,'guardianId',g.id,'guardianFamilyKey',g.family_key,'hasGuardianAccount',coalesce(g.has_account,false),
      'hasGuardianPhone',coalesce(length(g.phone_digits)>=10,false)
    ) order by s.name) from public.students s
    left join lateral (
      select guardian.id,guardian.name,regexp_replace(coalesce(guardian.phone,''),'\D','','g') phone_digits,
        exists(select 1 from public.student_guardians linked join public.guardians account_guardian on account_guardian.id=linked.guardian_id where linked.student_id=s.id and account_guardian.profile_id is not null) has_account,
        case when length(regexp_replace(coalesce(guardian.phone,''),'\D','','g'))>=10 then encode(digest(regexp_replace(guardian.phone,'\D','','g'),'sha256'),'hex') end family_key
      from public.student_guardians sg join public.guardians guardian on guardian.id=sg.guardian_id
      where sg.student_id=s.id order by sg.is_primary desc,guardian.created_at limit 1
    ) g on true
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

revoke all on function public.admin_account_invite_sms_board() from public,anon;
grant execute on function public.admin_account_invite_sms_board() to authenticated;
notify pgrst,'reload schema';
