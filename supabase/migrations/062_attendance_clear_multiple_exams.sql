-- 출결 기록 취소, 선택 결석 사유, 학생별 복수 시험 및 교직원 성적 추이를 지원합니다.

alter table public.lesson_exam_results
  drop constraint if exists lesson_exam_results_lesson_id_student_id_key;

create index if not exists lesson_exam_results_lesson_student_idx
  on public.lesson_exam_results(lesson_id, student_id, created_at);

create or replace function public.staff_clear_class_attendance(p_class_id uuid,p_date date,p_student_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 수정할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  select l.id into v_lesson_id from public.lessons l where l.class_id=p_class_id and l.lesson_date=p_date order by l.starts_at limit 1;
  if v_lesson_id is not null then delete from public.attendance a where a.lesson_id=v_lesson_id and a.student_id=p_student_id; end if;
end $$;

create or replace function public.staff_save_class_attendance(
  p_class_id uuid,p_date date,p_student_id uuid,p_status public.attendance_status,
  p_late_minutes integer default null,p_absence_reason text default null,p_note text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v_lesson_id uuid;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not exists(select 1 from public.enrollments e where e.class_id=p_class_id and e.student_id=p_student_id and e.status='active') then raise exception '이 클래스의 수강생이 아닙니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  insert into public.attendance as attendance_record(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(v_lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then nullif(trim(p_absence_reason),'') end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $$;

create or replace function public.staff_class_exam_results(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 시험 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',s.school,'grade',s.grade,
    'exams',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',coalesce(r.max_score,100),'evaluation',coalesce(r.evaluation,'')) order by r.created_at,r.id) from public.lesson_exam_results r where r.lesson_id=l.id and r.student_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb) into result
  from public.enrollments e join public.students s on s.id=e.student_id
  left join lateral(select lesson.id from public.lessons lesson where lesson.class_id=p_class_id and lesson.lesson_date=p_date order by lesson.starts_at limit 1) l on true
  where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_exam_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson uuid; v_student jsonb; v_exam jsonb; v_sid uuid; v_id uuid; v_keep uuid[]; v_score numeric; v_max numeric;
begin
  v_lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for v_student in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    v_sid:=(v_student->>'studentId')::uuid; v_keep:='{}'::uuid[];
    if not exists(select 1 from public.enrollments e where e.class_id=p_class_id and e.student_id=v_sid and e.status='active') then raise exception '이 클래스의 수강생이 아닌 학생이 포함되어 있습니다.'; end if;
    for v_exam in select value from jsonb_array_elements(coalesce(v_student->'exams','[]'::jsonb)) loop
      v_id:=nullif(v_exam->>'id','')::uuid; v_score:=nullif(v_exam->>'score','')::numeric; v_max:=coalesce(nullif(v_exam->>'maxScore','')::numeric,100);
      if v_max<=0 or (v_score is not null and (v_score<0 or v_score>v_max)) then raise exception '점수와 만점을 확인해 주세요.'; end if;
      if nullif(trim(v_exam->>'examType'),'') is null and nullif(trim(v_exam->>'examTitle'),'') is null and v_score is null and nullif(trim(v_exam->>'evaluation'),'') is null then continue; end if;
      if v_id is null then
        insert into public.lesson_exam_results(lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,created_by)
        values(v_lesson,v_sid,nullif(trim(v_exam->>'examType'),''),nullif(trim(v_exam->>'examTitle'),''),v_score,v_max,nullif(trim(v_exam->>'evaluation'),''),auth.uid()) returning id into v_id;
      else
        update public.lesson_exam_results r set exam_type=nullif(trim(v_exam->>'examType'),''),exam_title=nullif(trim(v_exam->>'examTitle'),''),score=v_score,max_score=v_max,evaluation=nullif(trim(v_exam->>'evaluation'),''),updated_at=now()
        where r.id=v_id and r.lesson_id=v_lesson and r.student_id=v_sid;
        if not found then raise exception '수정할 시험 기록을 찾을 수 없습니다.'; end if;
      end if;
      v_keep:=array_append(v_keep,v_id);
    end loop;
    delete from public.lesson_exam_results r where r.lesson_id=v_lesson and r.student_id=v_sid and not(r.id=any(v_keep));
  end loop;
end $$;

create or replace function public.staff_student_exam_progress(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 성적 추이를 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'lessonDate',l.lesson_date,'className',c.name,'subject',c.subject,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',r.max_score,'percent',case when r.score is null or coalesce(r.max_score,0)<=0 then null else round(r.score/r.max_score*100,1) end,'evaluation',coalesce(r.evaluation,'')) order by l.lesson_date,r.created_at) from public.lesson_exam_results r join public.lessons l on l.id=r.lesson_id join public.classes c on c.id=l.class_id where r.student_id=p_student_id),'[]'::jsonb);
end $$;

revoke all on function public.staff_clear_class_attendance(uuid,date,uuid),public.staff_save_class_attendance(uuid,date,uuid,public.attendance_status,integer,text,text),public.staff_class_exam_results(uuid,date),public.staff_save_class_exam_results(uuid,date,jsonb),public.staff_student_exam_progress(uuid) from public;
grant execute on function public.staff_clear_class_attendance(uuid,date,uuid),public.staff_save_class_attendance(uuid,date,uuid,public.attendance_status,integer,text,text),public.staff_class_exam_results(uuid,date),public.staff_save_class_exam_results(uuid,date,jsonb),public.staff_student_exam_progress(uuid) to authenticated;
notify pgrst,'reload schema';
