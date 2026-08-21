create or replace function public.staff_student_completed_learning_history(
  p_student_id uuid,
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare result jsonb; safe_limit integer;
begin
  if not public.is_staff() then raise exception '교직원만 학생 수업 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,300),500));

  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb)
  into result
  from (
    select item,lesson_date,starts_at from (
      select jsonb_set(
        jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))),
        '{source}','"regular"'::jsonb
      ) item,l.lesson_date,l.starts_at::text starts_at
      from jsonb_array_elements(coalesce(public.staff_student_learning_history(p_student_id,safe_limit),'[]'::jsonb)) entry(item)
      join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
      left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=p_student_id
      where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'

      union all

      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when l.kind='makeup' then '보강' else '추가수업' end,
        'source',l.kind,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
        'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),
        'examContent','',
        'attendance',case when a.attendance_status is null then null else jsonb_build_object(
          'status',a.attendance_status,'lateMinutes',a.late_minutes,
          'absenceReason',coalesce(a.absence_reason,''),'note','') end,
        'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object(
          'status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
        'exams',coalesce((select jsonb_agg(jsonb_build_object(
          'id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
          'score',e.score,'maxScore',e.max_score,
          'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,
          'evaluation',coalesce(e.evaluation,''),'feedback',''
        )) from public.teacher_special_lesson_exam_results e
          where e.session_id=l.id and e.student_id=p_student_id),'[]'::jsonb)
      ) item,l.lesson_date,l.starts_at::text starts_at
      from public.teacher_special_lessons l
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id
      join public.profiles p on p.id=l.teacher_profile_id
      where l.status='completed' and a.attendance_status is not null
    ) combined
    order by lesson_date desc,starts_at desc
    limit safe_limit
  ) limited;
  return result;
end $$;

create or replace function public.staff_student_special_lesson_insights(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  return jsonb_build_object(
    'attendance',jsonb_build_object(
      'attendanceTotal',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status is not null),
      'present',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='present'),
      'late',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='late'),
      'absent',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='absent')
    ),
    'upcomingMakeups',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.kind='makeup' and l.lesson_date>=current_date),
    'exams',coalesce((select jsonb_agg(to_jsonb(q) order by q."lessonDate",q.id) from (
      select e.id,l.lesson_date as "lessonDate",case when l.kind='makeup' then '개별 보강' else '추가수업' end as "className",
        case when l.kind='makeup' then '보강' else '추가수업' end as subject,
        coalesce(e.exam_type,'') as "examType",coalesce(e.exam_title,'') as "examTitle",
        e.score,coalesce(e.max_score,100) as "maxScore",
        case when e.score is null then null else round(e.score*100.0/coalesce(nullif(e.max_score,0),100),1) end as percent,
        coalesce(e.evaluation,'') as evaluation
      from public.teacher_special_lesson_exam_results e
      join public.teacher_special_lessons l on l.id=e.session_id
      where e.student_id=p_student_id and l.status='completed' and e.score is not null
      order by l.lesson_date desc,e.created_at desc limit 100
    ) q),'[]'::jsonb)
  );
end $$;

revoke all on function public.staff_student_completed_learning_history(uuid,integer),public.staff_student_special_lesson_insights(uuid) from public,anon;
grant execute on function public.staff_student_completed_learning_history(uuid,integer),public.staff_student_special_lesson_insights(uuid) to authenticated;
notify pgrst,'reload schema';
