-- A stale preview must never send a lesson excluded since it was opened.
create or replace function public.staff_claim_learning_alimtalk_current(p_student_id uuid,p_report_type text,p_period_start date,p_period_end date,p_lesson_summary text,p_attendance_summary text,p_learning_summary text,p_source_version text)
returns table(id uuid,recipient_phone text,guardian_name text,student_name text,template_variables jsonb)
language plpgsql security definer set search_path=public as $$
declare current_lessons jsonb; d date;
begin
 if not public.can_send_alimtalk() then raise exception '관리자만 알림톡을 발송할 수 있습니다.'; end if;
 if p_period_start is null or p_period_end is null or p_period_end<p_period_start or p_period_end-p_period_start>6 then raise exception '발송 기간을 확인해 주세요.'; end if;
 for d in select generate_series(p_period_start,p_period_end,interval '1 day')::date loop
  perform pg_advisory_xact_lock(hashtextextended('alimtalk-source:'||p_student_id||':'||d,0));
 end loop;
 select lessons into current_lessons from public.internal_alimtalk_report_sources(array[p_student_id],p_period_start,p_period_end);
 if coalesce(jsonb_array_length(current_lessons),0)=0 then raise exception '발송할 수업 기록이 없습니다. 대상을 새로고침해 주세요.'; end if;
 -- Older open tabs remain compatible until this student's participation has been changed.
 if p_source_version is null and not exists(select 1 from public.class_lesson_participation x where x.student_id=p_student_id and x.lesson_date between p_period_start and p_period_end) then
  return query select * from public.staff_claim_learning_alimtalk(p_student_id,p_report_type,p_period_start,p_period_end,p_lesson_summary,p_attendance_summary,p_learning_summary);
  return;
 end if;
 if p_source_version is distinct from md5(current_lessons::text) then raise exception '수업 기록 또는 수업 대상이 변경됐습니다. 대상을 새로고침하고 미리보기를 확인해 주세요.'; end if;
 return query select * from public.staff_claim_learning_alimtalk(p_student_id,p_report_type,p_period_start,p_period_end,p_lesson_summary,p_attendance_summary,p_learning_summary);
end $$;
revoke all on function public.staff_claim_learning_alimtalk_current(uuid,text,date,date,text,text,text,text) from public,anon;
grant execute on function public.staff_claim_learning_alimtalk_current(uuid,text,date,date,text,text,text,text) to authenticated;
