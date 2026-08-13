create table if not exists public.teacher_special_lessons (
  id uuid primary key default gen_random_uuid(),
  teacher_profile_id uuid not null references public.profiles(id) on delete cascade,
  lesson_date date not null,
  starts_at time not null,
  ends_at time not null,
  kind text not null default 'makeup' check (kind in ('makeup','additional')),
  room text,
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.teacher_special_lesson_students (
  session_id uuid not null references public.teacher_special_lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  primary key (session_id,student_id)
);

create index if not exists teacher_special_lessons_teacher_date_idx on public.teacher_special_lessons(teacher_profile_id,lesson_date,starts_at);
alter table public.teacher_special_lessons enable row level security;
alter table public.teacher_special_lesson_students enable row level security;

create policy teacher_special_lessons_staff on public.teacher_special_lessons for all to authenticated
using (public.is_staff() and (teacher_profile_id=auth.uid() or public.current_user_role()='admin'))
with check (public.is_staff() and (teacher_profile_id=auth.uid() or public.current_user_role()='admin'));
create policy teacher_special_lesson_students_staff on public.teacher_special_lesson_students for all to authenticated
using (public.is_staff() and exists(select 1 from public.teacher_special_lessons l where l.id=session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')))
with check (public.is_staff() and exists(select 1 from public.teacher_special_lessons l where l.id=session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')));

grant select,insert,update,delete on public.teacher_special_lessons,public.teacher_special_lesson_students to authenticated;

create or replace function public.staff_teacher_special_lessons(p_teacher_id uuid default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role='admin' then p_teacher_id else auth.uid() end;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',l.id,'date',l.lesson_date,'startTime',l.starts_at,'endTime',l.ends_at,'kind',l.kind,
    'room',l.room,'note',l.note,'teacherName',p.display_name,'teacherId',l.teacher_profile_id,
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by s.name)
      from public.teacher_special_lesson_students a join public.students s on s.id=a.student_id where a.session_id=l.id),'[]'::jsonb)
  ) order by l.lesson_date,l.starts_at) from public.teacher_special_lessons l join public.profiles p on p.id=l.teacher_profile_id
    where v_teacher is null or l.teacher_profile_id=v_teacher),'[]'::jsonb);
end $$;

create or replace function public.staff_special_lesson_student_options(p_teacher_id uuid default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=coalesce(p_teacher_id,auth.uid());
  if v_role<>'admin' then v_teacher:=auth.uid(); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'school',x.school,'grade',x.grade) order by x.name)
    from (select distinct s.id,s.name,s.school,s.grade from public.students s
      join public.enrollments e on e.student_id=s.id and e.status='active'
      join public.classes c on c.id=e.class_id and c.active
      join public.class_teachers ct on ct.class_id=c.id and ct.profile_id=v_teacher
      where s.status='active') x),'[]'::jsonb);
end $$;

create or replace function public.staff_save_teacher_special_lesson(
  p_id uuid,p_teacher_id uuid,p_date date,p_start_time time,p_end_time time,p_kind text,p_room text,p_note text,p_student_ids uuid[]
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; v_teacher uuid; v_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 저장할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role='admin' then coalesce(p_teacher_id,auth.uid()) else auth.uid() end;
  if p_kind not in ('makeup','additional') then raise exception '수업 구분을 확인해 주세요.'; end if;
  if p_end_time<=p_start_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if;
  if coalesce(array_length(p_student_ids,1),0)=0 then raise exception '학생을 한 명 이상 선택해 주세요.'; end if;
  if exists(select 1 from unnest(p_student_ids) sid where not exists(
    select 1 from public.enrollments e join public.classes c on c.id=e.class_id and c.active
    join public.class_teachers ct on ct.class_id=c.id and ct.profile_id=v_teacher
    join public.students s on s.id=e.student_id and s.status='active'
    where e.status='active' and e.student_id=sid
  )) then raise exception '담당 클래스의 재원생만 선택할 수 있습니다.'; end if;
  if p_id is null then
    insert into public.teacher_special_lessons(teacher_profile_id,lesson_date,starts_at,ends_at,kind,room,note,created_by)
    values(v_teacher,p_date,p_start_time,p_end_time,p_kind,nullif(trim(p_room),''),nullif(trim(p_note),''),auth.uid()) returning id into v_id;
  else
    update public.teacher_special_lessons set lesson_date=p_date,starts_at=p_start_time,ends_at=p_end_time,kind=p_kind,
      room=nullif(trim(p_room),''),note=nullif(trim(p_note),''),updated_at=now()
    where id=p_id and (teacher_profile_id=auth.uid() or v_role='admin') returning id into v_id;
    if v_id is null then raise exception '수정할 수 없는 일정입니다.'; end if;
  end if;
  delete from public.teacher_special_lesson_students where session_id=v_id;
  insert into public.teacher_special_lesson_students(session_id,student_id) select v_id,unnest(p_student_ids);
  return v_id;
end $$;

create or replace function public.staff_delete_teacher_special_lesson(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 삭제할 수 있습니다.'; end if;
  delete from public.teacher_special_lessons where id=p_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin');
  if not found then raise exception '삭제할 수 없는 일정입니다.'; end if;
end $$;

revoke all on function public.staff_teacher_special_lessons(uuid),public.staff_special_lesson_student_options(uuid),public.staff_save_teacher_special_lesson(uuid,uuid,date,time,time,text,text,text,uuid[]),public.staff_delete_teacher_special_lesson(uuid) from public;
grant execute on function public.staff_teacher_special_lessons(uuid),public.staff_special_lesson_student_options(uuid),public.staff_save_teacher_special_lesson(uuid,uuid,date,time,time,text,text,text,uuid[]),public.staff_delete_teacher_special_lesson(uuid) to authenticated;
notify pgrst,'reload schema';
