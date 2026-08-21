-- Bring individual makeup/additional lessons into the same learning-report flow as regular classes.

alter table public.teacher_special_lessons
  add column if not exists status text not null default 'draft'
  check (status in ('draft','completed'));

alter table public.teacher_special_lesson_students
  add column if not exists lesson_content text;

create table if not exists public.family_special_lesson_report_reads (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.teacher_special_lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  unique (session_id, student_id, viewer_profile_id)
);

create index if not exists family_special_lesson_reads_student_idx
  on public.family_special_lesson_report_reads(student_id, viewer_profile_id, viewed_at desc);

alter table public.family_special_lesson_report_reads enable row level security;
drop policy if exists family_special_read_own_receipts on public.family_special_lesson_report_reads;
create policy family_special_read_own_receipts
on public.family_special_lesson_report_reads for select to authenticated
using (viewer_profile_id = auth.uid());
grant select on public.family_special_lesson_report_reads to authenticated;

create or replace function public.staff_special_lesson_board(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() or not exists(
    select 1 from public.teacher_special_lessons l
    where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')
  ) then raise exception '확인할 수 없는 수업입니다.'; end if;
  return (select jsonb_build_object(
    'notice',coalesce(l.class_notice,''),
    'state',coalesce(l.status,'draft'),
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,
      'status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,
      'lessonContent',coalesce(a.lesson_content,''),
      'assignedHomework',coalesce(a.assigned_homework,''),
      'inspectionStatus',coalesce(a.inspection_status,''),
      'inspectionNote',coalesce(a.inspection_note,''),
      'previousHomework',coalesce((
        select prior_a.assigned_homework
        from public.teacher_special_lesson_students prior_a
        join public.teacher_special_lessons prior_l on prior_l.id=prior_a.session_id
        where prior_a.student_id=s.id and prior_l.teacher_profile_id=l.teacher_profile_id
          and prior_l.lesson_date<l.lesson_date and nullif(trim(prior_a.assigned_homework),'') is not null
        order by prior_l.lesson_date desc,prior_l.starts_at desc limit 1
      ),''),
      'exam',coalesce((select jsonb_build_object(
        'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
        'score',e.score,'maxScore',e.max_score,'evaluation',coalesce(e.evaluation,'')
      ) from public.teacher_special_lesson_exam_results e
        where e.session_id=l.id and e.student_id=s.id),'{}'::jsonb)
    ) order by s.name)
      from public.teacher_special_lesson_students a
      join public.students s on s.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) from public.teacher_special_lessons l where l.id=p_session_id);
end $$;

create or replace function public.staff_save_special_lesson_learning(
  p_session_id uuid,p_notice text,p_rows jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; sid uuid; exam jsonb;
begin
  if not public.is_staff() or not exists(
    select 1 from public.teacher_special_lessons l
    where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')
  ) then raise exception '저장할 수 없는 수업입니다.'; end if;
  update public.teacher_special_lessons
  set class_notice=nullif(trim(p_notice),''),updated_at=now() where id=p_session_id;
  for item in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid;
    if exists(select 1 from public.teacher_special_lesson_students where session_id=p_session_id and student_id=sid) then
      update public.teacher_special_lesson_students set
        lesson_content=nullif(trim(item->>'lessonContent'),''),
        assigned_homework=nullif(trim(item->>'assignedHomework'),''),
        inspection_status=nullif(trim(item->>'inspectionStatus'),''),
        inspection_note=nullif(trim(item->>'inspectionNote'),''),
        updated_at=now()
      where session_id=p_session_id and student_id=sid;
      exam:=coalesce(item->'exam','{}'::jsonb);
      if nullif(trim(exam->>'examType'),'') is null
         and nullif(trim(exam->>'examTitle'),'') is null
         and nullif(exam->>'score','') is null then
        delete from public.teacher_special_lesson_exam_results
        where session_id=p_session_id and student_id=sid;
      else
        insert into public.teacher_special_lesson_exam_results(
          session_id,student_id,exam_type,exam_title,score,max_score,evaluation
        ) values(
          p_session_id,sid,nullif(trim(exam->>'examType'),''),
          nullif(trim(exam->>'examTitle'),''),nullif(exam->>'score','')::numeric,
          coalesce(nullif(exam->>'maxScore','')::numeric,100),
          nullif(trim(exam->>'evaluation'),'')
        )
        on conflict(session_id,student_id) do update set
          exam_type=excluded.exam_type,exam_title=excluded.exam_title,score=excluded.score,
          max_score=excluded.max_score,evaluation=excluded.evaluation,updated_at=now();
      end if;
    end if;
  end loop;
end $$;

create or replace function public.staff_set_special_lesson_state(p_session_id uuid,p_state text)
returns text language plpgsql security definer set search_path=public as $$
declare missing_names text;
begin
  if not public.is_staff() or not exists(
    select 1 from public.teacher_special_lessons l
    where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')
  ) then raise exception '수업 완료 상태를 변경할 수 없습니다.'; end if;
  if p_state not in ('draft','completed') then raise exception '수업 상태를 확인해 주세요.'; end if;
  if p_state='completed' then
    select string_agg(s.name,', ' order by s.name) into missing_names
    from public.teacher_special_lesson_students a join public.students s on s.id=a.student_id
    where a.session_id=p_session_id and a.attendance_status is null;
    if missing_names is not null then raise exception '출결 미입력 학생: %',missing_names; end if;
  end if;
  update public.teacher_special_lessons set status=p_state,updated_at=now() where id=p_session_id;
  return p_state;
end $$;

create or replace function public.staff_special_lesson_family_report_read_status(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_completed boolean; v_students jsonb; v_total integer:=0; v_linked integer:=0; v_confirmed integer:=0;
begin
  if not public.is_staff() or not exists(
    select 1 from public.teacher_special_lessons l
    where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')
  ) then raise exception '학부모 확인 현황을 볼 수 없습니다.'; end if;
  select status='completed' into v_completed from public.teacher_special_lessons where id=p_session_id;
  select count(*)::integer,
    count(*) filter(where guardian_count>0)::integer,
    count(*) filter(where guardian_count>0 and read_count>0)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'studentId',student_id,'studentName',student_name,'school',school,'grade',grade,
      'guardianCount',guardian_count,'readCount',read_count,
      'status',case when guardian_count=0 then 'unlinked' when read_count>0 then 'confirmed' else 'unconfirmed' end,
      'viewedAt',viewed_at
    ) order by student_name),'[]'::jsonb)
  into v_total,v_linked,v_confirmed,v_students
  from (
    select s.id student_id,s.name student_name,s.school,s.grade,
      (select count(distinct g.profile_id)::integer from public.student_guardians sg
       join public.guardians g on g.id=sg.guardian_id
       where sg.student_id=s.id and g.profile_id is not null) guardian_count,
      case when not coalesce(v_completed,false) then 0 else (
        select count(distinct r.viewer_profile_id)::integer
        from public.family_special_lesson_report_reads r
        join public.guardians g on g.profile_id=r.viewer_profile_id
        join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=s.id
        where r.session_id=p_session_id and r.student_id=s.id
      ) end read_count,
      case when not coalesce(v_completed,false) then null else (
        select max(r.viewed_at) from public.family_special_lesson_report_reads r
        join public.guardians g on g.profile_id=r.viewer_profile_id
        join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=s.id
        where r.session_id=p_session_id and r.student_id=s.id
      ) end viewed_at
    from public.teacher_special_lesson_students a join public.students s on s.id=a.student_id
    where a.session_id=p_session_id
  ) student_rows;
  return jsonb_build_object(
    'lessonId',case when v_completed then p_session_id else null end,
    'totalStudents',coalesce(v_total,0),'linkedStudents',coalesce(v_linked,0),
    'confirmedStudents',coalesce(v_confirmed,0),
    'unconfirmedStudents',greatest(coalesce(v_linked,0)-coalesce(v_confirmed,0),0),
    'unlinkedStudents',greatest(coalesce(v_total,0)-coalesce(v_linked,0),0),
    'students',coalesce(v_students,'[]'::jsonb)
  );
end $$;

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
      where l.status='completed'
      union all
      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when l.kind='makeup' then '보강' else '추가수업' end,
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
      left join public.profiles p on p.id=l.teacher_profile_id
      where l.status='completed' and l.lesson_date<=current_date
    ) combined order by lesson_date desc,starts_at desc limit safe_limit
  ) limited;
  return result;
end $$;

create or replace function public.family_learning_report_reads(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare viewer_role public.user_role; selected_id uuid; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role='student' then select id into selected_id from public.students where profile_id=auth.uid();
  elsif viewer_role='guardian' then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
  else raise exception '학생 또는 학부모 계정만 학습리포트 확인 상태를 볼 수 있습니다.'; end if;
  if selected_id is null or selected_id<>p_student_id then raise exception '연결된 학생의 학습리포트만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(item order by viewed_at desc),'[]'::jsonb) into result from (
    select jsonb_build_object('lessonId',lesson_id,'viewedAt',viewed_at) item,viewed_at
    from public.family_learning_report_reads where student_id=selected_id and viewer_profile_id=auth.uid()
    union all
    select jsonb_build_object('lessonId',session_id,'viewedAt',viewed_at),viewed_at
    from public.family_special_lesson_report_reads where student_id=selected_id and viewer_profile_id=auth.uid()
  ) reads;
  return result;
end $$;

create or replace function public.mark_family_learning_report_read(p_student_id uuid,p_lesson_id uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare viewer_role public.user_role; selected_id uuid; result timestamptz;
begin
  viewer_role:=public.current_user_role();
  if viewer_role='student' then select id into selected_id from public.students where profile_id=auth.uid();
  elsif viewer_role='guardian' then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
  else raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.'; end if;
  if selected_id is null or selected_id<>p_student_id then raise exception '연결된 학생의 학습리포트만 확인할 수 있습니다.'; end if;
  if exists(select 1 from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id where l.id=p_lesson_id and a.student_id=selected_id and l.status='completed') then
    insert into public.family_special_lesson_report_reads(session_id,student_id,viewer_profile_id,viewed_at)
    values(p_lesson_id,selected_id,auth.uid(),now())
    on conflict(session_id,student_id,viewer_profile_id) do update set viewed_at=excluded.viewed_at
    returning viewed_at into result;
  elsif exists(select 1 from public.lessons l join public.enrollments e on e.class_id=l.class_id and e.student_id=selected_id where l.id=p_lesson_id) then
    insert into public.family_learning_report_reads(lesson_id,student_id,viewer_profile_id,viewed_at)
    values(p_lesson_id,selected_id,auth.uid(),now())
    on conflict(lesson_id,student_id,viewer_profile_id) do update set viewed_at=excluded.viewed_at
    returning viewed_at into result;
  else raise exception '확인할 수 없는 학습리포트입니다.'; end if;
  return result;
end $$;

revoke all on function public.staff_special_lesson_board(uuid),public.staff_save_special_lesson_learning(uuid,text,jsonb),public.staff_set_special_lesson_state(uuid,text),public.staff_special_lesson_family_report_read_status(uuid),public.family_completed_learning_reports(uuid,integer),public.family_learning_report_reads(uuid),public.mark_family_learning_report_read(uuid,uuid) from public,anon;
grant execute on function public.staff_special_lesson_board(uuid),public.staff_save_special_lesson_learning(uuid,text,jsonb),public.staff_set_special_lesson_state(uuid,text),public.staff_special_lesson_family_report_read_status(uuid),public.family_completed_learning_reports(uuid,integer),public.family_learning_report_reads(uuid),public.mark_family_learning_report_read(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
