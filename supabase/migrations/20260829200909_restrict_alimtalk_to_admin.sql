-- 알림톡 발송은 관리자 계정에서만 조회·생성할 수 있습니다.

drop policy if exists learning_alimtalk_staff_rows on public.learning_alimtalk_deliveries;
create policy learning_alimtalk_admin_rows on public.learning_alimtalk_deliveries
for select to authenticated using (public.current_user_role()='admin');

create or replace function public.staff_alimtalk_recipient(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 알림톡 발송 정보를 확인할 수 있습니다.'; end if;
  select jsonb_build_object('guardianName',g.name,'maskedPhone',left(regexp_replace(g.phone,'\D','','g'),3)||'-****-'||right(regexp_replace(g.phone,'\D','','g'),4),'available',true)
  into result from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
  where sg.student_id=p_student_id and length(regexp_replace(coalesce(g.phone,''),'\D','','g')) between 10 and 11
  order by sg.is_primary desc,g.created_at limit 1;
  return coalesce(result,jsonb_build_object('guardianName','','maskedPhone','','available',false));
end $$;

create or replace function public.staff_alimtalk_delivery_list()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.current_user_role()='admin' then coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'studentId',d.student_id,'studentName',s.name,'reportType',d.report_type,'periodStart',d.period_start,
    'status',d.status,'sentAt',d.sent_at,'errorMessage',d.error_message
  ) order by d.created_at desc),'[]'::jsonb) else '[]'::jsonb end
  from (select * from public.learning_alimtalk_deliveries order by created_at desc limit 300) d
  join public.students s on s.id=d.student_id
$$;

create or replace function public.staff_claim_learning_alimtalk(
  p_student_id uuid,p_report_type text,p_period_start date,p_period_end date,
  p_lesson_summary text,p_attendance_summary text,p_learning_summary text
) returns table(id uuid,recipient_phone text,guardian_name text,student_name text,template_variables jsonb)
language plpgsql security definer set search_path=public as $$
declare target_guardian public.guardians%rowtype; delivery_id uuid; student_label text; variables jsonb;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 알림톡을 발송할 수 있습니다.'; end if;
  if p_report_type not in ('daily','weekly') or p_period_end<p_period_start or p_period_end-p_period_start>6 then raise exception '발송 기간을 확인해 주세요.'; end if;
  if length(trim(coalesce(p_lesson_summary,''))) not between 1 and 180 or length(trim(coalesce(p_attendance_summary,''))) not between 1 and 100 or length(trim(coalesce(p_learning_summary,''))) not between 1 and 180 then raise exception '알림톡 요약 내용을 확인해 주세요.'; end if;
  select g.* into target_guardian from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
  where sg.student_id=p_student_id and length(regexp_replace(coalesce(g.phone,''),'\D','','g')) between 10 and 11 order by sg.is_primary desc,g.created_at limit 1;
  if target_guardian.id is null then raise exception '발송 가능한 학부모 연락처가 없습니다.'; end if;
  select name into student_label from public.students where students.id=p_student_id;
  variables:=jsonb_build_object('studentName',student_label,'periodStart',p_period_start,'periodEnd',p_period_end,'lessonSummary',trim(p_lesson_summary),'attendanceSummary',trim(p_attendance_summary),'learningSummary',trim(p_learning_summary));
  insert into public.learning_alimtalk_deliveries(student_id,guardian_id,report_type,period_start,period_end,template_variables,status,created_by)
  values(p_student_id,target_guardian.id,p_report_type,p_period_start,p_period_end,variables,'sending',auth.uid())
  on conflict(student_id,guardian_id,report_type,period_start) do update set period_end=excluded.period_end,template_variables=excluded.template_variables,status='sending',error_message=null,updated_at=now(),created_by=auth.uid()
  where public.learning_alimtalk_deliveries.status in ('draft','failed') returning public.learning_alimtalk_deliveries.id into delivery_id;
  if delivery_id is null then raise exception '이미 발송했거나 현재 발송 중인 기록입니다.'; end if;
  return query select delivery_id,regexp_replace(target_guardian.phone,'\D','','g'),target_guardian.name,student_label,variables;
end $$;

notify pgrst,'reload schema';
