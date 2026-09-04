-- 관리자 알림톡 원문 확인 및 동일 내용 재발송 이력을 지원합니다.

create table public.learning_alimtalk_resend_attempts (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.learning_alimtalk_deliveries(id) on delete cascade,
  status text not null check (status in ('sent','failed')),
  provider_message_id text,
  provider_group_id text,
  error_message text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create index learning_alimtalk_resend_attempt_delivery_idx
on public.learning_alimtalk_resend_attempts(delivery_id,created_at desc);

alter table public.learning_alimtalk_resend_attempts enable row level security;
create policy learning_alimtalk_resend_admin_rows
on public.learning_alimtalk_resend_attempts for select to authenticated
using (public.current_user_role()='admin');

create or replace function public.staff_alimtalk_delivery_list()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.current_user_role()='admin' then coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'studentId',d.student_id,'studentName',s.name,'reportType',d.report_type,'periodStart',d.period_start,
    'status',d.status,'sentAt',coalesce(a.last_sent_at,d.sent_at),'errorMessage',d.error_message,
    'templateVariables',d.template_variables,
    'maskedPhone',left(regexp_replace(g.phone,'\D','','g'),3)||'-****-'||right(regexp_replace(g.phone,'\D','','g'),4),
    'sendCount',case when d.status='sent' then 1 else 0 end+coalesce(a.sent_count,0)
  ) order by coalesce(a.last_sent_at,d.sent_at,d.created_at) desc),'[]'::jsonb) else '[]'::jsonb end
  from (select * from public.learning_alimtalk_deliveries order by created_at desc limit 300) d
  join public.students s on s.id=d.student_id
  join public.guardians g on g.id=d.guardian_id
  left join lateral (
    select count(*) filter (where r.status='sent')::int as sent_count,
      max(r.sent_at) filter (where r.status='sent') as last_sent_at
    from public.learning_alimtalk_resend_attempts r where r.delivery_id=d.id
  ) a on true
$$;

create or replace function public.staff_prepare_learning_alimtalk_resend(p_delivery_id uuid)
returns table(delivery_id uuid,recipient_phone text,guardian_name text,student_name text,report_type text,template_variables jsonb)
language plpgsql security definer set search_path=public as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 알림톡을 재발송할 수 있습니다.'; end if;
  return query
  select d.id,regexp_replace(g.phone,'\D','','g'),g.name,s.name,d.report_type,d.template_variables
  from public.learning_alimtalk_deliveries d
  join public.guardians g on g.id=d.guardian_id
  join public.students s on s.id=d.student_id
  where d.id=p_delivery_id and d.status='sent'
    and length(regexp_replace(coalesce(g.phone,''),'\D','','g')) between 10 and 11;
  if not found then raise exception '재발송할 원본 기록이나 학부모 연락처를 찾지 못했습니다.'; end if;
end $$;

create or replace function public.internal_log_learning_alimtalk_resend(
  p_delivery_id uuid,p_status text,p_provider_message_id text,p_provider_group_id text,p_error_message text,p_created_by uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare attempt_id uuid;
begin
  if p_status not in ('sent','failed') then raise exception '올바른 발송 상태가 필요합니다.'; end if;
  insert into public.learning_alimtalk_resend_attempts(delivery_id,status,provider_message_id,provider_group_id,error_message,created_by,sent_at)
  values(p_delivery_id,p_status,nullif(p_provider_message_id,''),nullif(p_provider_group_id,''),
    case when p_status='failed' then left(coalesce(nullif(trim(p_error_message),''),'알림톡 재발송에 실패했습니다.'),500) else null end,
    p_created_by,case when p_status='sent' then now() else null end)
  returning id into attempt_id;
  return attempt_id;
end $$;

revoke all on function public.staff_alimtalk_delivery_list(),public.staff_prepare_learning_alimtalk_resend(uuid) from public,anon;
grant execute on function public.staff_alimtalk_delivery_list(),public.staff_prepare_learning_alimtalk_resend(uuid) to authenticated;
revoke all on function public.internal_log_learning_alimtalk_resend(uuid,text,text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.internal_log_learning_alimtalk_resend(uuid,text,text,text,text,uuid) to service_role;
notify pgrst,'reload schema';
