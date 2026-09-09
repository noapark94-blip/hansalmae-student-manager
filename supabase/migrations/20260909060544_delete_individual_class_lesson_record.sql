-- Delete one student's regular-class record without affecting the shared lesson or other students.

create or replace function public.staff_delete_class_student_record(
  p_class_id uuid,
  p_date date,
  p_student_id uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_lesson_id uuid;
begin
  if not public.is_staff() then
    raise exception '교직원만 학생별 수업 기록을 삭제할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if not exists(select 1 from public.students where id=p_student_id) then
    raise exception '학생 정보를 찾을 수 없습니다.';
  end if;

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date
  order by starts_at
  limit 1
  for update;

  if v_lesson_id is null then return; end if;

  delete from public.learning_report_comments
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.family_learning_report_reads
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.family_notifications
  where source_type='learning_report'
    and source_id=v_lesson_id
    and student_id=p_student_id;

  delete from public.lesson_exam_results
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.lesson_homework_results
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.attendance
  where lesson_id=v_lesson_id and student_id=p_student_id;

  update public.class_lesson_revision_drafts d
  set payload=jsonb_set(
    d.payload,
    '{rows}',
    coalesce((
      select jsonb_agg(entry.item order by entry.ordinality)
      from jsonb_array_elements(coalesce(d.payload->'rows','[]'::jsonb))
        with ordinality as entry(item,ordinality)
      where entry.item->>'studentId'<>p_student_id::text
    ),'[]'::jsonb),
    true
  ),
  saved_at=now(),
  saved_by=auth.uid()
  where d.lesson_id=v_lesson_id;
end;
$$;

revoke all on function public.staff_delete_class_student_record(uuid,date,uuid)
from public,anon,authenticated;
grant execute on function public.staff_delete_class_student_record(uuid,date,uuid)
to authenticated;

-- A completed regular-class report is visible only while that student's attendance record exists.
create or replace function public.family_completed_learning_reports(
  p_student_id uuid default null,p_limit integer default 10
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare viewer_role public.user_role; selected_id uuid; safe_limit integer; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.';
  end if;
  if viewer_role='student' then
    select s.id into selected_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학습리포트만 확인할 수 있습니다.'; end if;
  else
    select s.id into selected_id from public.guardians g
    join public.student_guardians sg on sg.guardian_id=g.id
    join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and (p_student_id is null or s.id=p_student_id)
    order by sg.is_primary desc,s.name limit 1;
    if selected_id is null then raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.'; end if;
  end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,10),30));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (
    select item,lesson_date,starts_at from (
      select jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))) item,
        l.lesson_date,l.starts_at::text starts_at
      from jsonb_array_elements(coalesce(public.family_learning_reports(selected_id,30),'[]'::jsonb)) entry(item)
      join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
      left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
      where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
      union all
      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when l.kind='makeup' then '보강' else '추가수업' end,
        'mainSubject',coalesce(sub.name,''),
        'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
        'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),
        'examContent','',
        'attendance',case when a.attendance_status is null then null else jsonb_build_object(
          'status',a.attendance_status,'lateMinutes',a.late_minutes,
          'absenceReason',coalesce(a.absence_reason,''),'note','') end,
        'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object(
          'status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
        'exams',coalesce((select jsonb_agg(jsonb_build_object(
          'id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
          'score',e.score,'maxScore',coalesce(e.max_score,100),
          'percent',case when e.score is null or coalesce(e.max_score,0)<=0 then null else round(e.score/e.max_score*100,1) end,
          'evaluation',coalesce(e.evaluation,''),'feedback',coalesce(e.evaluation,'')
        )) from public.teacher_special_lesson_exam_results e
          where e.session_id=l.id and e.student_id=selected_id),'[]'::jsonb)
      ) item,l.lesson_date,l.starts_at::text starts_at
      from public.teacher_special_lessons l
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
      left join public.academy_subjects sub on sub.id=l.subject_id
      left join public.profiles p on p.id=l.teacher_profile_id
      where l.status='completed' and l.lesson_date<=current_date
    ) combined order by lesson_date desc,starts_at desc limit safe_limit
  ) limited;
  return result;
end $$;

revoke all on function public.family_completed_learning_reports(uuid,integer)
from public,anon;
grant execute on function public.family_completed_learning_reports(uuid,integer)
to authenticated;

notify pgrst,'reload schema';
