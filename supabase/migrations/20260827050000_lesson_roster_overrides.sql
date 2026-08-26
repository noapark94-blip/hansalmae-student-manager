-- 선택한 수업 날짜에만 누락 학생을 보정합니다. 실제 수강 시작일·종료일은 변경하지 않습니다.
create table if not exists public.class_lesson_roster_overrides (
  class_id uuid not null references public.classes(id) on delete cascade,
  lesson_date date not null,
  student_id uuid not null references public.students(id) on delete cascade,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (class_id, lesson_date, student_id)
);

create index if not exists class_lesson_roster_overrides_student_idx
  on public.class_lesson_roster_overrides(student_id, lesson_date desc);
create index if not exists class_lesson_roster_overrides_added_by_idx
  on public.class_lesson_roster_overrides(added_by) where added_by is not null;

alter table public.class_lesson_roster_overrides enable row level security;
revoke all on table public.class_lesson_roster_overrides from public, anon, authenticated;
drop policy if exists "assigned_staff_read_lesson_roster_overrides" on public.class_lesson_roster_overrides;
create policy "assigned_staff_read_lesson_roster_overrides"
on public.class_lesson_roster_overrides for select to authenticated
using (
  public.current_user_role()='admin'
  or exists(select 1 from public.class_teachers ct where ct.class_id=class_lesson_roster_overrides.class_id and ct.profile_id=auth.uid())
);

-- 기존 요일별 배정 규칙에 날짜별 직접 추가를 함께 인정합니다.
create or replace function public.student_attends_class_on(p_student_id uuid,p_class_id uuid,p_date date)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.class_lesson_roster_overrides o
    where o.student_id=p_student_id and o.class_id=p_class_id and o.lesson_date=p_date
  ) or case when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
    then exists(select 1 from public.student_schedule_assignments ssa join public.class_schedules cs on cs.id=ssa.class_schedule_id
      where ssa.student_id=p_student_id and cs.class_id=p_class_id and cs.weekday=extract(isodow from p_date)::smallint)
    else exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.class_id=p_class_id and e.status='active'
      and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)) end;
$$;

create or replace function public.staff_lesson_roster_override_options(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 날짜별 수업 명단을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',s.status,
    'standardIncluded',(
      case when exists(select 1 from public.student_schedule_assignments where student_id=s.id)
        then exists(select 1 from public.student_schedule_assignments ssa join public.class_schedules cs on cs.id=ssa.class_schedule_id
          where ssa.student_id=s.id and cs.class_id=p_class_id and cs.weekday=extract(isodow from p_date)::smallint)
        else exists(select 1 from public.enrollments e where e.student_id=s.id and e.class_id=p_class_id and e.status='active'
          and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)) end
    ),
    'directlyAdded',exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id)
  ) order by
    exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id) desc,
    s.name),'[]'::jsonb) into result
  from public.students s;
  return result;
end $$;

create or replace function public.staff_set_lesson_roster_override(p_class_id uuid,p_date date,p_student_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson uuid;
begin
  if not public.is_staff() then raise exception '교직원만 날짜별 수업 명단을 수정할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생 정보를 찾지 못했습니다.'; end if;
  if p_date>(timezone('Asia/Seoul',now()))::date then raise exception '지난 수업 또는 오늘 수업만 직접 보정할 수 있습니다.'; end if;

  if p_active then
    insert into public.class_lesson_roster_overrides(class_id,lesson_date,student_id,added_by)
    values(p_class_id,p_date,p_student_id,auth.uid()) on conflict do nothing;
  else
    select id into v_lesson from public.lessons where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1;
    if v_lesson is not null and (
      exists(select 1 from public.attendance where lesson_id=v_lesson and student_id=p_student_id)
      or exists(select 1 from public.lesson_exam_results where lesson_id=v_lesson and student_id=p_student_id)
      or exists(select 1 from public.lesson_homework_results where lesson_id=v_lesson and student_id=p_student_id)
    ) then raise exception '이미 저장된 출결·시험·숙제 기록이 있어 명단에서 제외할 수 없습니다.'; end if;
    delete from public.class_lesson_roster_overrides where class_id=p_class_id and lesson_date=p_date and student_id=p_student_id;
  end if;
end $$;

create or replace function public.staff_class_day(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('lessonId',l.id,'examContent',null,'lessonContent',null,'homeworkContent',null,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,
      'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note,
      'directAdded',exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id)
    ) order by s.name)
      from public.students s left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join lateral(select lesson.* from public.lessons lesson where lesson.class_id=c.id and lesson.lesson_date=p_date order by lesson.starts_at limit 1) l on true where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $$;

create or replace function public.staff_class_exam_results(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 시험 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',s.school,'grade',s.grade,
    'exams',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',coalesce(r.max_score,100),'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.feedback,'')) order by r.created_at,r.id) from public.lesson_exam_results r where r.lesson_id=l.id and r.student_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select lesson.id from public.lessons lesson where lesson.class_id=p_class_id and lesson.lesson_date=p_date order by lesson.starts_at limit 1) l on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_exam_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
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
end $$;

create or replace function public.staff_class_homework_results(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'lessonContent',coalesce(current_result.lesson_content,''),'assignedHomework',coalesce(current_result.assigned_homework,''),'inspectionStatus',coalesce(current_result.inspection_status,current_result.status,''),'inspectionNote',coalesce(current_result.inspection_note,current_result.note,''),'previousHomework',coalesce(previous_result.assigned_homework,'')) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1) lesson on true
  left join public.lesson_homework_results current_result on current_result.lesson_id=lesson.id and current_result.student_id=s.id
  left join lateral(select hr.assigned_homework from public.lesson_homework_results hr join public.lessons prior on prior.id=hr.lesson_id where prior.class_id=p_class_id and prior.lesson_date<p_date and hr.student_id=s.id and nullif(trim(hr.assigned_homework),'') is not null order by prior.lesson_date desc limit 1) previous_result on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_homework_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
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
end $$;

create or replace function public.staff_save_class_attendance(p_class_id uuid,p_date date,p_student_id uuid,p_status public.attendance_status,p_late_minutes integer default null,p_absence_reason text default null,p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson_id uuid;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not public.student_attends_class_on(p_student_id,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생입니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  insert into public.attendance as attendance_record(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(v_lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then trim(p_absence_reason) end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $$;

create or replace function public.staff_set_class_lesson_state(p_class_id uuid,p_date date,p_state text)
returns text language plpgsql security definer set search_path=public as $$
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
end $$;

revoke all on function public.staff_lesson_roster_override_options(uuid,date),public.staff_set_lesson_roster_override(uuid,date,uuid,boolean) from public,anon;
grant execute on function public.staff_lesson_roster_override_options(uuid,date),public.staff_set_lesson_roster_override(uuid,date,uuid,boolean) to authenticated;

revoke all on function public.student_attends_class_on(uuid,uuid,date),public.staff_class_day(uuid,date),public.staff_class_exam_results(uuid,date),public.staff_save_class_exam_results(uuid,date,jsonb),public.staff_class_homework_results(uuid,date),public.staff_save_class_homework_results(uuid,date,jsonb),public.staff_save_class_attendance(uuid,date,uuid,public.attendance_status,integer,text,text),public.staff_set_class_lesson_state(uuid,date,text) from public,anon;
grant execute on function public.student_attends_class_on(uuid,uuid,date),public.staff_class_day(uuid,date),public.staff_class_exam_results(uuid,date),public.staff_save_class_exam_results(uuid,date,jsonb),public.staff_class_homework_results(uuid,date),public.staff_save_class_homework_results(uuid,date,jsonb),public.staff_save_class_attendance(uuid,date,uuid,public.attendance_status,integer,text,text),public.staff_set_class_lesson_state(uuid,date,text) to authenticated;

notify pgrst,'reload schema';
