create or replace function public.staff_class_exam_results(p_class_id uuid,p_date date) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 시험 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',s.school,'grade',s.grade,
    'exams',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',coalesce(r.max_score,100),'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.feedback,'')) order by r.created_at,r.id) from public.lesson_exam_results r where r.lesson_id=l.id and r.student_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb) into result
  from public.enrollments e join public.students s on s.id=e.student_id
  left join lateral(select lesson.id from public.lessons lesson where lesson.class_id=p_class_id and lesson.lesson_date=p_date order by lesson.starts_at limit 1) l on true
  where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_exam_results(p_class_id uuid,p_date date,p_results jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare v_lesson uuid; v_student jsonb; v_exam jsonb; v_sid uuid; v_id uuid; v_score numeric; v_max numeric;
begin
  v_lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for v_student in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    v_sid:=(v_student->>'studentId')::uuid;
    if not exists(select 1 from public.enrollments e where e.class_id=p_class_id and e.student_id=v_sid and e.status='active') then raise exception '이 클래스의 수강생이 아닌 학생이 포함되어 있습니다.'; end if;
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
end $$;

notify pgrst,'reload schema';
