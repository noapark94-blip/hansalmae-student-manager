-- 회원가입 초대 문자 발송 상태를 저장하고 관리자 문자 화면에서 확인합니다.

alter table public.account_invites
  add column if not exists recipient_name text,
  add column if not exists recipient_phone text,
  add column if not exists sms_sent_at timestamptz,
  add column if not exists sms_attempts integer not null default 0,
  add column if not exists sms_last_error text,
  add column if not exists sms_provider_message_id text;

create index if not exists account_invites_sms_status_idx
  on public.account_invites(role, sms_sent_at, used_at, created_at desc);

create or replace function public.admin_account_invite_sms_board()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.current_user_role()='admin' then jsonb_build_object(
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,
        'hasStudentAccount',s.profile_id is not null,
        'hasStudentPhone',nullif(regexp_replace(coalesce(s.phone,''),'\D','','g'),'') is not null,
        'guardianName',g.name,
        'hasGuardianAccount',g.profile_id is not null,
        'hasGuardianPhone',nullif(regexp_replace(coalesce(g.phone,''),'\D','','g'),'') is not null
      ) order by s.name)
      from public.students s
      left join lateral (
        select guardian.name,guardian.phone,guardian.profile_id
        from public.student_guardians sg
        join public.guardians guardian on guardian.id=sg.guardian_id
        where sg.student_id=s.id
        order by sg.is_primary desc,guardian.created_at
        limit 1
      ) g on true
      where s.status in ('active','재원')
    ),'[]'::jsonb),
    'invites',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'role',i.role,'studentId',i.student_id,
        'targetName',coalesce(i.recipient_name,s.name,case i.role when 'teacher' then '새 선생님' else '초대 대상' end),
        'studentName',s.name,'maskedPhone',case when nullif(regexp_replace(coalesce(i.recipient_phone,''),'\D','','g'),'') is null then null else left(regexp_replace(i.recipient_phone,'\D','','g'),3)||'-****-'||right(regexp_replace(i.recipient_phone,'\D','','g'),4) end,
        'codeHint',i.code_hint,'createdAt',i.created_at,'expiresAt',i.expires_at,
        'smsSentAt',i.sms_sent_at,'smsAttempts',i.sms_attempts,'smsLastError',i.sms_last_error,
        'usedAt',i.used_at,'revokedAt',i.revoked_at,
        'status',case
          when i.used_at is not null then 'joined'
          when i.sms_sent_at is not null then 'sent'
          when i.sms_last_error is not null then 'failed'
          else 'unsent'
        end
      ) order by i.created_at desc)
      from (select * from public.account_invites order by created_at desc limit 200) i
      left join public.students s on s.id=i.student_id
      where i.role in ('student','guardian','teacher')
        and (i.revoked_at is null or i.used_at is not null)
    ),'[]'::jsonb)
  ) else null end
$$;

revoke all on function public.admin_account_invite_sms_board() from public;
grant execute on function public.admin_account_invite_sms_board() to authenticated;
