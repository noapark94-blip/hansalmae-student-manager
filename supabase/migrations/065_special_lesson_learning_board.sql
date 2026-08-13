alter table public.teacher_special_lessons
  add column if not exists class_notice text;

alter table public.teacher_special_lesson_students
  add column if not exists attendance_status text check (attendance_status in ('present','late','absent')),
  add column if not exists late_minutes integer check (late_minutes is null or late_minutes > 0),
  add column if not exists absence_reason text,
  add column if not exists assigned_homework text,
  add column if not exists inspection_status text,
  add column if not exists inspection_note text,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.teacher_special_lesson_exam_results (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.teacher_special_lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  exam_type text,
  exam_title text,
  score numeric,
  max_score numeric not null default 100 check (max_score > 0),
  evaluation text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id,student_id)
);

alter table public.teacher_special_lesson_exam_results enable row level security;
create policy teacher_special_lesson_exam_results_staff on public.teacher_special_lesson_exam_results for all to authenticated
using (public.is_staff() and exists(select 1 from public.teacher_special_lessons l where l.id=session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')))
with check (public.is_staff() and exists(select 1 from public.teacher_special_lessons l where l.id=session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')));
grant select,insert,update,delete on public.teacher_special_lesson_exam_results to authenticated;

create or replace function public.staff_special_lesson_board(p_session_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() or not exists(select 1 from public.teacher_special_lessons l where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')) then raise exception '확인할 수 없는 수업입니다.'; end if;
  return (select jsonb_build_object(
    'notice',coalesce(l.class_notice,''),
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,
      'status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,
      'assignedHomework',coalesce(a.assigned_homework,''),'inspectionStatus',coalesce(a.inspection_status,''),'inspectionNote',coalesce(a.inspection_note,''),
      'previousHomework',coalesce((select prior_a.assigned_homework from public.teacher_special_lesson_students prior_a join public.teacher_special_lessons prior_l on prior_l.id=prior_a.session_id where prior_a.student_id=s.id and prior_l.teacher_profile_id=l.teacher_profile_id and prior_l.lesson_date<l.lesson_date and nullif(trim(prior_a.assigned_homework),'') is not null order by prior_l.lesson_date desc,prior_l.starts_at desc limit 1),''),
      'exam',coalesce((select jsonb_build_object('examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'evaluation',coalesce(e.evaluation,'')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=s.id),'{}'::jsonb)
    ) order by s.name) from public.teacher_special_lesson_students a join public.students s on s.id=a.student_id where a.session_id=l.id),'[]'::jsonb)
  ) from public.teacher_special_lessons l where l.id=p_session_id);
end $$;

create or replace function public.staff_save_special_lesson_attendance(p_session_id uuid,p_student_id uuid,p_status text,p_late_minutes integer,p_absence_reason text) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() or not exists(select 1 from public.teacher_special_lessons l where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')) then raise exception '저장할 수 없는 수업입니다.'; end if;
  if p_status is not null and p_status not in ('present','late','absent') then raise exception '출결 상태를 확인해 주세요.'; end if;
  update public.teacher_special_lesson_students set attendance_status=p_status,late_minutes=case when p_status='late' then p_late_minutes end,absence_reason=case when p_status='absent' then nullif(trim(p_absence_reason),'') end,updated_at=now() where session_id=p_session_id and student_id=p_student_id;
end $$;

create or replace function public.staff_save_special_lesson_learning(p_session_id uuid,p_notice text,p_rows jsonb) returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; sid uuid; exam jsonb;
begin
  if not public.is_staff() or not exists(select 1 from public.teacher_special_lessons l where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')) then raise exception '저장할 수 없는 수업입니다.'; end if;
  update public.teacher_special_lessons set class_notice=nullif(trim(p_notice),''),updated_at=now() where id=p_session_id;
  for item in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid;
    if exists(select 1 from public.teacher_special_lesson_students where session_id=p_session_id and student_id=sid) then
      update public.teacher_special_lesson_students set assigned_homework=nullif(trim(item->>'assignedHomework'),''),inspection_status=nullif(trim(item->>'inspectionStatus'),''),inspection_note=nullif(trim(item->>'inspectionNote'),''),updated_at=now() where session_id=p_session_id and student_id=sid;
      exam:=coalesce(item->'exam','{}'::jsonb);
      if nullif(trim(exam->>'examType'),'') is null and nullif(trim(exam->>'examTitle'),'') is null and nullif(exam->>'score','') is null then
        delete from public.teacher_special_lesson_exam_results where session_id=p_session_id and student_id=sid;
      else
        insert into public.teacher_special_lesson_exam_results(session_id,student_id,exam_type,exam_title,score,max_score,evaluation)
        values(p_session_id,sid,nullif(trim(exam->>'examType'),''),nullif(trim(exam->>'examTitle'),''),nullif(exam->>'score','')::numeric,coalesce(nullif(exam->>'maxScore','')::numeric,100),nullif(trim(exam->>'evaluation'),''))
        on conflict(session_id,student_id) do update set exam_type=excluded.exam_type,exam_title=excluded.exam_title,score=excluded.score,max_score=excluded.max_score,evaluation=excluded.evaluation,updated_at=now();
      end if;
    end if;
  end loop;
end $$;

revoke all on function public.staff_special_lesson_board(uuid),public.staff_save_special_lesson_attendance(uuid,uuid,text,integer,text),public.staff_save_special_lesson_learning(uuid,text,jsonb) from public;
grant execute on function public.staff_special_lesson_board(uuid),public.staff_save_special_lesson_attendance(uuid,uuid,text,integer,text),public.staff_save_special_lesson_learning(uuid,text,jsonb) to authenticated;

-- 학생 명단을 수정해도 기존에 남긴 출결·학습 기록은 유지한다.
create or replace function public.staff_save_teacher_special_lesson(
  p_id uuid,p_teacher_id uuid,p_date date,p_start_time time,p_end_time time,p_kind text,
  p_room text,p_note text,p_student_ids uuid[]
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_teacher uuid:=coalesce(p_teacher_id,auth.uid());
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and v_teacher<>auth.uid()) then raise exception '저장 권한이 없습니다.'; end if;
  if p_kind not in ('makeup','additional') or p_end_time<=p_start_time then raise exception '수업 구분과 시간을 확인해 주세요.'; end if;
  if coalesce(array_length(p_student_ids,1),0)=0 then raise exception '학생을 한 명 이상 선택해 주세요.'; end if;
  if p_id is null then
    insert into public.teacher_special_lessons(teacher_profile_id,lesson_date,starts_at,ends_at,lesson_kind,room,note)
    values(v_teacher,p_date,p_start_time,p_end_time,p_kind,nullif(trim(p_room),''),nullif(trim(p_note),'')) returning id into v_id;
  else
    if not exists(select 1 from public.teacher_special_lessons where id=p_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin')) then raise exception '수정 권한이 없습니다.'; end if;
    update public.teacher_special_lessons set teacher_profile_id=v_teacher,lesson_date=p_date,starts_at=p_start_time,ends_at=p_end_time,lesson_kind=p_kind,room=nullif(trim(p_room),''),note=nullif(trim(p_note),''),updated_at=now() where id=p_id returning id into v_id;
  end if;
  delete from public.teacher_special_lesson_exam_results where session_id=v_id and not (student_id=any(p_student_ids));
  delete from public.teacher_special_lesson_students where session_id=v_id and not (student_id=any(p_student_ids));
  insert into public.teacher_special_lesson_students(session_id,student_id)
  select v_id,student_id from unnest(p_student_ids) student_id on conflict do nothing;
  return v_id;
end $$;

revoke all on function public.staff_save_teacher_special_lesson(uuid,uuid,date,time,time,text,text,text,uuid[]) from public;
grant execute on function public.staff_save_teacher_special_lesson(uuid,uuid,date,time,time,text,text,text,uuid[]) to authenticated;
notify pgrst,'reload schema';
