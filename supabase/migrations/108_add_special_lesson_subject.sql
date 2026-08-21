alter table public.teacher_special_lessons
  add column if not exists subject_id uuid references public.academy_subjects(id) on delete restrict;

create index if not exists teacher_special_lessons_subject_idx
  on public.teacher_special_lessons(subject_id);

create or replace function public.staff_teacher_special_lessons(p_teacher_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role='admin' then p_teacher_id else auth.uid() end;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',l.id,'date',l.lesson_date,'startTime',l.starts_at,'endTime',l.ends_at,'kind',l.kind,
    'subjectId',l.subject_id,'subject',s.name,'mainSubject',s.main_subject,
    'room',l.room,'note',l.note,'teacherName',p.display_name,'teacherId',l.teacher_profile_id,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'name',st.name,'school',st.school,'grade',st.grade,
      'attendanceStatus',a.attendance_status
    ) order by st.name)
      from public.teacher_special_lesson_students a
      join public.students st on st.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) order by l.lesson_date,l.starts_at)
  from public.teacher_special_lessons l
  join public.profiles p on p.id=l.teacher_profile_id
  left join public.academy_subjects s on s.id=l.subject_id
  where v_teacher is null or l.teacher_profile_id=v_teacher),'[]'::jsonb);
end $$;

create or replace function public.staff_save_teacher_special_lesson(
  p_id uuid,p_teacher_id uuid,p_date date,p_start_time time,p_end_time time,p_kind text,
  p_room text,p_note text,p_student_ids uuid[],p_subject_id uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_teacher uuid:=coalesce(p_teacher_id,auth.uid());
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and v_teacher<>auth.uid()) then raise exception '저장 권한이 없습니다.'; end if;
  if p_kind not in ('makeup','additional') or p_end_time<=p_start_time then raise exception '수업 구분과 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.academy_subjects where id=p_subject_id and active) then raise exception '수업 과목을 선택해 주세요.'; end if;
  if coalesce(array_length(p_student_ids,1),0)=0 then raise exception '학생을 한 명 이상 선택해 주세요.'; end if;
  if p_id is null then
    insert into public.teacher_special_lessons(teacher_profile_id,lesson_date,starts_at,ends_at,kind,subject_id,room,note,created_by)
    values(v_teacher,p_date,p_start_time,p_end_time,p_kind,p_subject_id,nullif(trim(p_room),''),nullif(trim(p_note),''),auth.uid()) returning id into v_id;
  else
    update public.teacher_special_lessons set teacher_profile_id=v_teacher,lesson_date=p_date,starts_at=p_start_time,ends_at=p_end_time,
      kind=p_kind,subject_id=p_subject_id,room=nullif(trim(p_room),''),note=nullif(trim(p_note),''),updated_at=now()
    where id=p_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin') returning id into v_id;
    if v_id is null then raise exception '수정 권한이 없습니다.'; end if;
  end if;
  delete from public.teacher_special_lesson_exam_results where session_id=v_id and not(student_id=any(p_student_ids));
  delete from public.teacher_special_lesson_students where session_id=v_id and not(student_id=any(p_student_ids));
  insert into public.teacher_special_lesson_students(session_id,student_id) select v_id,student_id from unnest(p_student_ids) student_id on conflict do nothing;
  return v_id;
end $$;

revoke all on function public.staff_save_teacher_special_lesson(uuid,uuid,date,time,time,text,text,text,uuid[],uuid) from public,anon;
grant execute on function public.staff_save_teacher_special_lesson(uuid,uuid,date,time,time,text,text,text,uuid[],uuid) to authenticated;

create or replace function public.staff_student_completed_learning_history(p_student_id uuid,p_limit integer default 300)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; safe_limit integer;
begin
  if not public.is_staff() then raise exception '교직원만 학생 수업 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,300),500));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (select item,lesson_date,starts_at from (
    select jsonb_set(jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))),'{source}','"regular"'::jsonb) item,
      l.lesson_date,l.starts_at::text starts_at
    from jsonb_array_elements(coalesce(public.staff_student_learning_history(p_student_id,safe_limit),'[]'::jsonb)) entry(item)
    join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
    left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=p_student_id
    where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
    union all
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',l.kind,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=p_student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id
    join public.profiles p on p.id=l.teacher_profile_id
    left join public.academy_subjects s on s.id=l.subject_id
    where l.status='completed' and a.attendance_status is not null
  ) combined order by lesson_date desc,starts_at desc limit safe_limit) limited;
  return result;
end $$;

revoke all on function public.staff_teacher_special_lessons(uuid),public.staff_student_completed_learning_history(uuid,integer) from public,anon;
grant execute on function public.staff_teacher_special_lessons(uuid),public.staff_student_completed_learning_history(uuid,integer) to authenticated;
notify pgrst,'reload schema';
