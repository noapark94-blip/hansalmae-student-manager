CREATE OR REPLACE FUNCTION public.staff_class_daily_notice(p_class_id uuid, p_date date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 반 공지를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  return (select content from public.class_daily_notices where class_id=p_class_id and notice_date=p_date);
end $function$;

CREATE OR REPLACE FUNCTION public.staff_save_class_attendance(p_class_id uuid, p_date date, p_student_id uuid, p_status attendance_status, p_late_minutes integer DEFAULT NULL::integer, p_absence_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not public.student_attends_class_on(p_student_id,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생입니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  insert into public.attendance as attendance_record(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(v_lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then trim(p_absence_reason) end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_save_class_daily_notice(p_class_id uuid, p_date date, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 반 공지를 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if nullif(trim(p_content),'') is null then delete from public.class_daily_notices where class_id=p_class_id and notice_date=p_date;
  else insert into public.class_daily_notices(class_id,notice_date,content,created_by) values(p_class_id,p_date,trim(p_content),auth.uid())
    on conflict(class_id,notice_date) do update set content=excluded.content,created_by=auth.uid(),updated_at=now(); end if;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_save_class_exam_results(p_class_id uuid, p_date date, p_results jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson uuid; v_student jsonb; v_exam jsonb; v_sid uuid; v_id uuid; v_score numeric; v_max numeric;
begin
  v_lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for v_student in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    v_sid:=(v_student->>'studentId')::uuid;
    if not public.student_attends_class_on(v_sid,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.'; end if;
    v_exam:=coalesce(v_student->'exams'->0,'{}'::jsonb);
    v_id:=nullif(v_exam->>'id','')::uuid; v_score:=nullif(v_exam->>'score','')::numeric; v_max:=coalesce(nullif(v_exam->>'maxScore','')::numeric,100);
    if v_max<=0 or (v_score is not null and (v_score<0 or v_score>v_max)) then raise exception '점수와 만점을 확인해 주세요.'; end if;
    if nullif(trim(v_exam->>'examType'),'') is null and nullif(trim(v_exam->>'examTitle'),'') is null and v_score is null and nullif(trim(v_exam->>'evaluation'),'') is null and nullif(trim(v_exam->>'feedback'),'') is null then continue; end if;
    if v_id is null then
      insert into public.lesson_exam_results(lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,feedback,created_by)
      values(v_lesson,v_sid,nullif(trim(v_exam->>'examType'),''),nullif(trim(v_exam->>'examTitle'),''),v_score,v_max,nullif(trim(v_exam->>'evaluation'),''),nullif(trim(v_exam->>'feedback'),''),auth.uid());
    else
      update public.lesson_exam_results set exam_type=nullif(trim(v_exam->>'examType'),''),exam_title=nullif(trim(v_exam->>'examTitle'),''),score=v_score,max_score=v_max,evaluation=nullif(trim(v_exam->>'evaluation'),''),feedback=nullif(trim(v_exam->>'feedback'),''),updated_at=now()
      where id=v_id and lesson_id=v_lesson and student_id=v_sid;
    end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_save_class_homework_results(p_class_id uuid, p_date date, p_results jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lesson uuid; item jsonb; sid uuid; individual_lesson text; assigned text; inspection text; inspection_memo text;
begin
  lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid;
    if not public.student_attends_class_on(sid,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.'; end if;
    individual_lesson:=nullif(trim(item->>'lessonContent'),''); assigned:=nullif(trim(item->>'assignedHomework'),''); inspection:=nullif(item->>'inspectionStatus',''); inspection_memo:=nullif(trim(item->>'inspectionNote'),'');
    if inspection is not null and inspection not in ('complete','partial','missing','excused') then raise exception '숙제 검사 상태를 확인해 주세요.'; end if;
    if individual_lesson is null and assigned is null and inspection is null and inspection_memo is null then delete from public.lesson_homework_results where lesson_id=lesson and student_id=sid;
    else insert into public.lesson_homework_results(lesson_id,student_id,lesson_content,assigned_homework,inspection_status,inspection_note,status,note,created_by) values(lesson,sid,individual_lesson,assigned,inspection,inspection_memo,inspection,inspection_memo,auth.uid())
      on conflict(lesson_id,student_id) do update set lesson_content=excluded.lesson_content,assigned_homework=excluded.assigned_homework,inspection_status=excluded.inspection_status,inspection_note=excluded.inspection_note,status=excluded.status,note=excluded.note,updated_at=now(); end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_save_class_lesson_content(p_class_id uuid, p_date date, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수업내용을 저장할 수 있습니다.'; end if;
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  update public.lessons set lesson_content=nullif(trim(coalesce(p_content,'')),''),updated_at=now(),teacher_profile_id=auth.uid() where id=v_lesson_id;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_set_class_lesson_state(p_class_id uuid, p_date date, p_state text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid; missing_names text;
begin
  if not public.is_staff() then raise exception '교직원만 수업 상태를 변경할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if p_state not in ('draft','completed') then raise exception '수업 상태를 확인해 주세요.'; end if;
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if p_state='completed' then
    select string_agg(s.name,', ' order by s.name) into missing_names from public.students s
    where public.student_attends_class_on(s.id,p_class_id,p_date)
      and not exists(select 1 from public.attendance a where a.lesson_id=v_lesson_id and a.student_id=s.id);
    if missing_names is not null then raise exception '출결 미입력 학생: %',missing_names; end if;
  end if;
  update public.lessons set status=p_state,updated_at=now() where id=v_lesson_id;
  return p_state;
end $function$;
