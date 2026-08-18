-- 한살매 학습노트 1차 마감: 공통 수업내용 저장, 이전 수업 템플릿, 학생별 숙제 리포트 정확도 보완

create or replace function public.staff_class_lesson_content(p_class_id uuid,p_date date)
returns text language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 수업내용을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;
  return coalesce((select l.lesson_content from public.lessons l where l.class_id=p_class_id and l.lesson_date=p_date order by l.starts_at limit 1),'');
end $$;

create or replace function public.staff_save_class_lesson_content(p_class_id uuid,p_date date,p_content text)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수업내용을 저장할 수 있습니다.'; end if;
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  update public.lessons set lesson_content=nullif(trim(coalesce(p_content,'')),''),updated_at=now(),teacher_profile_id=auth.uid() where id=v_lesson_id;
end $$;

create or replace function public.staff_class_previous_learning_template(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_lesson public.lessons; v_notice text; v_exam jsonb; v_homework text;
begin
  if not public.is_staff() then raise exception '교직원만 이전 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;
  select * into v_lesson from public.lessons where class_id=p_class_id and lesson_date<p_date order by lesson_date desc,starts_at desc limit 1;
  if v_lesson.id is null then return null; end if;
  select content into v_notice from public.class_daily_notices where class_id=p_class_id and notice_date=v_lesson.lesson_date;
  select jsonb_build_object('examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'maxScore',coalesce(er.max_score,100),'evaluation',coalesce(er.evaluation,''))
    into v_exam from public.lesson_exam_results er where er.lesson_id=v_lesson.id and (nullif(trim(er.exam_type),'') is not null or nullif(trim(er.exam_title),'') is not null) order by er.updated_at desc limit 1;
  select hr.assigned_homework into v_homework from public.lesson_homework_results hr where hr.lesson_id=v_lesson.id and nullif(trim(hr.assigned_homework),'') is not null order by hr.updated_at desc limit 1;
  return jsonb_build_object('lessonDate',to_char(v_lesson.lesson_date,'YYYY-MM-DD'),'lessonContent',coalesce(v_lesson.lesson_content,''),'notice',coalesce(v_notice,''),'exam',coalesce(v_exam,'{}'::jsonb),'assignedHomework',coalesce(v_homework,''));
end $$;

create or replace function public.family_learning_reports(p_student_id uuid default null,p_limit integer default 10)
returns jsonb language plpgsql stable security definer set search_path=public as $$
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
      'lessonContent',coalesce(l.lesson_content,''),'homeworkContent',coalesce(hr.assigned_homework,l.homework_content,''),'examContent',coalesce(l.exam_content,''),
      'attendance',case when a.id is null then null else jsonb_build_object('status',a.status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note',coalesce(a.note,'')) end,
      'homeworkResult',case when hr.id is null then null else jsonb_build_object('status',coalesce(hr.inspection_status,hr.status,''),'note',coalesce(hr.inspection_note,hr.note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id),'[]'::jsonb)
    ) report_row,l.lesson_date,l.starts_at
    from public.lessons l join public.classes c on c.id=l.class_id join public.enrollments e on e.class_id=c.id and e.student_id=selected_id
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
    where e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date) and l.lesson_date<=current_date and (a.id is not null or hr.id is not null or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or exists(select 1 from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id))
    order by l.lesson_date desc,l.starts_at desc limit safe_limit
  ) reports;
  return result;
end $$;

revoke all on function public.staff_class_lesson_content(uuid,date),public.staff_save_class_lesson_content(uuid,date,text),public.staff_class_previous_learning_template(uuid,date) from public;
grant execute on function public.staff_class_lesson_content(uuid,date),public.staff_save_class_lesson_content(uuid,date,text),public.staff_class_previous_learning_template(uuid,date) to authenticated;
revoke all on function public.family_learning_reports(uuid,integer) from public;
grant execute on function public.family_learning_reports(uuid,integer) to authenticated;
notify pgrst,'reload schema';
