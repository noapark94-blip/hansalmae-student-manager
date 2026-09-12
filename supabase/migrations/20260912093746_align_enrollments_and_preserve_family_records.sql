CREATE OR REPLACE FUNCTION public.family_learning_reports(p_student_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; safe_limit integer; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select s.id into selected_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학습리포트만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.'; end if;
    end if;
  end if;
  if selected_id is null then return '[]'::jsonb; end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,10),30));
  select coalesce(jsonb_agg(report_row order by lesson_date desc,starts_at desc),'[]'::jsonb) into result from (
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',l.starts_at,'classId',c.id,'className',c.name,'subject',c.subject,'room',coalesce(l.room,c.room),'teacherName',coalesce(tp.display_name,'담당 선생님'),
      'lessonContent',coalesce(l.lesson_content,''),'classNotice',coalesce(n.content,''),'homeworkContent',coalesce(hr.assigned_homework,l.homework_content,''),'examContent',coalesce(l.exam_content,''),
      'attendance',case when a.id is null then null else jsonb_build_object('status',a.status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note',coalesce(a.note,'')) end,
      'homeworkResult',case when hr.id is null then null else jsonb_build_object('status',coalesce(hr.inspection_status,hr.status,''),'note',coalesce(hr.inspection_note,hr.note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id),'[]'::jsonb)
    ) report_row,l.lesson_date,l.starts_at
    from public.lessons l join public.classes c on c.id=l.class_id 
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
    left join public.class_daily_notices n on n.class_id=l.class_id and n.notice_date=l.lesson_date
    where (exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=selected_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)) or (l.status='completed' and a.id is not null)) and l.lesson_date<=current_date and (a.id is not null or hr.id is not null or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or exists(select 1 from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id))
    order by l.lesson_date desc,l.starts_at desc limit safe_limit
  ) reports;
  return result;
end $function$
;
create or replace function public.staff_sync_student_enrollments(p_student_id uuid,p_class_ids uuid[] default '{}'::uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare requested uuid[]:=coalesce(p_class_ids,'{}'::uuid[]); cid uuid;
begin
 if not coalesce(public.is_staff(),false) then raise exception '교직원만 학생 수강 클래스를 변경할 수 있습니다.'; end if;
 if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
 if exists(select 1 from unnest(requested) r where r is null or not exists(select 1 from public.classes where id=r and active)) then raise exception '운영 중인 클래스만 수강에 배정할 수 있습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
 for cid in select distinct class_id from (
 select class_id from public.enrollments where student_id=p_student_id and status='active'
 union select cs.class_id from public.student_schedule_assignments s join public.class_schedules cs on cs.id=s.class_schedule_id where s.student_id=p_student_id
 ) x where not(class_id=any(requested)) loop
 perform public.staff_set_class_enrollment(cid,p_student_id,false);
 end loop;
 for cid in select distinct r from unnest(requested) r loop
 if exists(select 1 from public.student_schedule_assignments s join public.class_schedules cs on cs.id=s.class_schedule_id where s.student_id=p_student_id and cs.class_id=cid) then
 perform public.staff_save_class_student_schedule_assignments(cid,p_student_id,(select array_agg(s.class_schedule_id) from public.student_schedule_assignments s join public.class_schedules cs on cs.id=s.class_schedule_id where s.student_id=p_student_id and cs.class_id=cid));
 else perform public.staff_set_class_enrollment(cid,p_student_id,true);
 end if;
 end loop;
end $$;