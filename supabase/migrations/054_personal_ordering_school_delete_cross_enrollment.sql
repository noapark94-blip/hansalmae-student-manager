-- 사용자별 목록 순서, 안전한 학교 삭제, 요일별 교차수강 배정

create table if not exists public.user_ui_preferences (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  menu_layout jsonb,
  class_order uuid[] not null default '{}',
  school_order uuid[] not null default '{}',
  updated_at timestamptz not null default now()
);
alter table public.user_ui_preferences enable row level security;
drop policy if exists "users_manage_own_ui_preferences" on public.user_ui_preferences;
create policy "users_manage_own_ui_preferences" on public.user_ui_preferences
  for all to authenticated using (profile_id=auth.uid()) with check (profile_id=auth.uid());
grant select,insert,update on public.user_ui_preferences to authenticated;

create or replace function public.get_app_menu_layout()
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(
    (select menu_layout from public.user_ui_preferences where profile_id=auth.uid()),
    (select layout from public.app_menu_settings where id='main')
  );
$$;

create or replace function public.save_app_menu_layout(p_layout jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if jsonb_typeof(p_layout)<>'object' or jsonb_typeof(p_layout->'folders')<>'array' or jsonb_array_length(p_layout->'folders')=0 then
    raise exception '메뉴 폴더 구성이 올바르지 않습니다.';
  end if;
  insert into public.user_ui_preferences(profile_id,menu_layout,updated_at)
  values(auth.uid(),p_layout,now())
  on conflict(profile_id) do update set menu_layout=excluded.menu_layout,updated_at=now();
  return p_layout;
end $$;

create or replace function public.user_list_preferences()
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'classOrder',coalesce((select to_jsonb(class_order) from public.user_ui_preferences where profile_id=auth.uid()),'[]'::jsonb),
    'schoolOrder',coalesce((select to_jsonb(school_order) from public.user_ui_preferences where profile_id=auth.uid()),'[]'::jsonb)
  );
$$;

create or replace function public.save_user_class_order(p_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 클래스 순서를 저장할 수 있습니다.'; end if;
  insert into public.user_ui_preferences(profile_id,class_order,updated_at) values(auth.uid(),coalesce(p_ids,'{}'),now())
  on conflict(profile_id) do update set class_order=excluded.class_order,updated_at=now();
end $$;

create or replace function public.save_user_school_order(p_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 학교 순서를 저장할 수 있습니다.'; end if;
  insert into public.user_ui_preferences(profile_id,school_order,updated_at) values(auth.uid(),coalesce(p_ids,'{}'),now())
  on conflict(profile_id) do update set school_order=excluded.school_order,updated_at=now();
end $$;

create or replace function public.staff_registration_schools()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by
    coalesce(array_position((select school_order from public.user_ui_preferences where profile_id=auth.uid()),s.id),2147483647),s.name),'[]'::jsonb) else '[]'::jsonb end
  from public.academy_schools s where s.active;
$$;

create or replace function public.staff_student_registration_classes()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'subject',coalesce(s.name,c.subject),'subject_id',c.subject_id,
    'room',c.room,'color',c.color,'active',c.active
  ) order by coalesce(array_position((select class_order from public.user_ui_preferences where profile_id=auth.uid()),c.id),2147483647),coalesce(s.name,c.subject),c.name),'[]'::jsonb) else '[]'::jsonb end
  from public.classes c left join public.academy_subjects s on s.id=c.subject_id where c.active;
$$;

create or replace function public.staff_delete_school(p_school_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare target_name text;
begin
  if not public.is_staff() then raise exception '교직원만 학교를 삭제할 수 있습니다.'; end if;
  select name into target_name from public.academy_schools where id=p_school_id and active;
  if target_name is null then raise exception '학교를 찾을 수 없습니다.'; end if;
  if exists(select 1 from public.students where lower(regexp_replace(coalesce(school,''),'[[:space:]]+','','g'))=lower(regexp_replace(target_name,'[[:space:]]+','','g'))) then
    raise exception '이 학교를 사용 중인 학생이 있어 삭제할 수 없습니다. 학생의 학교를 먼저 변경해 주세요.';
  end if;
  update public.academy_schools set active=false where id=p_school_id;
end $$;

create table if not exists public.student_schedule_assignments (
  student_id uuid not null references public.students(id) on delete cascade,
  class_schedule_id uuid not null references public.class_schedules(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(student_id,class_schedule_id)
);
alter table public.student_schedule_assignments enable row level security;
drop policy if exists "staff_read_student_schedule_assignments" on public.student_schedule_assignments;
create policy "staff_read_student_schedule_assignments" on public.student_schedule_assignments for select to authenticated using(public.is_staff());
grant select on public.student_schedule_assignments to authenticated;

create or replace function public.can_manage_student_schedule(p_student_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.current_user_role()='admin' or exists(
    select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
    where e.student_id=p_student_id and e.status='active' and ct.profile_id=auth.uid()
  );
$$;

create or replace function public.staff_student_schedule_choices(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_manage_student_schedule(p_student_id) then raise exception '관리자 또는 담당 선생님만 교차수강을 배정할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'scheduleId',cs.id,'classId',c.id,'className',c.name,'subject',c.subject,'color',c.color,
    'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,
    'assigned',exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id=p_student_id and ssa.class_schedule_id=cs.id)
  ) order by c.subject,cs.weekday,cs.start_time,c.name),'[]'::jsonb) into result
  from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id
  where e.student_id=p_student_id and e.status='active' and c.active and (cs.valid_until is null or cs.valid_until>=current_date);
  return result;
end $$;

create or replace function public.staff_save_student_schedule_assignments(p_student_id uuid,p_schedule_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_manage_student_schedule(p_student_id) then raise exception '관리자 또는 담당 선생님만 교차수강을 배정할 수 있습니다.'; end if;
  if exists(select 1 from unnest(coalesce(p_schedule_ids,'{}')) requested where not exists(
    select 1 from public.class_schedules cs join public.enrollments e on e.class_id=cs.class_id
    where cs.id=requested and e.student_id=p_student_id and e.status='active'
  )) then raise exception '현재 수강 중인 클래스의 시간만 배정할 수 있습니다.'; end if;
  delete from public.student_schedule_assignments where student_id=p_student_id;
  insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
  select p_student_id,id,auth.uid() from unnest(coalesce(p_schedule_ids,'{}')) id;
end $$;

-- 요일별 배정이 하나라도 있으면 해당 날짜에 배정된 클래스 출석부에만 학생을 표시합니다.
create or replace function public.student_attends_class_on(p_student_id uuid,p_class_id uuid,p_date date)
returns boolean language sql stable security definer set search_path=public as $$
  select case when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
    then exists(select 1 from public.student_schedule_assignments ssa join public.class_schedules cs on cs.id=ssa.class_schedule_id
      where ssa.student_id=p_student_id and cs.class_id=p_class_id and cs.weekday=extract(isodow from p_date)::smallint)
    else exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.class_id=p_class_id and e.status='active'
      and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)) end;
$$;

create or replace function public.staff_class_day(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('lessonId',l.id,'examContent',l.exam_content,'lessonContent',l.lesson_content,'homeworkContent',l.homework_content,
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note) order by s.name)
      from public.enrollments e join public.students s on s.id=e.student_id left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join public.lessons l on l.class_id=c.id and l.lesson_date=p_date where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $$;

revoke all on function public.save_app_menu_layout(jsonb),public.user_list_preferences(),public.save_user_class_order(uuid[]),public.save_user_school_order(uuid[]),public.staff_delete_school(uuid),public.can_manage_student_schedule(uuid),public.staff_student_schedule_choices(uuid),public.staff_save_student_schedule_assignments(uuid,uuid[]),public.student_attends_class_on(uuid,uuid,date) from public;
grant execute on function public.save_app_menu_layout(jsonb),public.user_list_preferences(),public.save_user_class_order(uuid[]),public.save_user_school_order(uuid[]),public.staff_delete_school(uuid),public.can_manage_student_schedule(uuid),public.staff_student_schedule_choices(uuid),public.staff_save_student_schedule_assignments(uuid,uuid[]),public.student_attends_class_on(uuid,uuid,date),public.get_app_menu_layout(),public.staff_registration_schools(),public.staff_student_registration_classes(),public.staff_class_day(uuid,date) to authenticated;
notify pgrst,'reload schema';
