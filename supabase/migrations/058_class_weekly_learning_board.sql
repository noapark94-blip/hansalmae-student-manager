-- 클래스 한 화면에서 주간 출석, 학생별 시험 결과와 숙제 상태를 함께 관리합니다.

create table public.lesson_homework_results (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text check (status is null or status in ('complete','partial','missing','excused')),
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_id, student_id)
);

alter table public.lesson_homework_results enable row level security;

create policy "assigned_staff_read_homework_results"
on public.lesson_homework_results for select to authenticated using (
  public.current_user_role() = 'admin' or exists (
    select 1
    from public.lessons l
    join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_id and ct.profile_id = auth.uid()
  )
);

create policy "assigned_staff_manage_homework_results"
on public.lesson_homework_results for all to authenticated using (
  public.current_user_role() = 'admin' or exists (
    select 1
    from public.lessons l
    join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_id and ct.profile_id = auth.uid()
  )
) with check (
  public.current_user_role() = 'admin' or exists (
    select 1
    from public.lessons l
    join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_id and ct.profile_id = auth.uid()
  )
);

create or replace function public.staff_class_homework_results(p_class_id uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 숙제 결과만 확인할 수 있습니다.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,
    'status',coalesce(hr.status,''),
    'note',coalesce(hr.note,'')
  ) order by s.name),'[]'::jsonb)
  into result
  from public.enrollments e
  join public.students s on s.id=e.student_id
  left join lateral (
    select id from public.lessons
    where class_id=p_class_id and lesson_date=p_date
    order by starts_at limit 1
  ) l on true
  left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=s.id
  where e.class_id=p_class_id and e.status='active'
    and public.student_attends_class_on(s.id,p_class_id,p_date);

  return result;
end $$;

create or replace function public.staff_save_class_homework_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson_id uuid; item jsonb; v_student_id uuid; homework_status text; homework_note text;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    v_student_id:=(item->>'studentId')::uuid;
    homework_status:=nullif(item->>'status','');
    homework_note:=nullif(trim(item->>'note'),'');
    if homework_status is not null and homework_status not in ('complete','partial','missing','excused') then
      raise exception '숙제 상태를 확인해 주세요.';
    end if;
    if not exists(
      select 1 from public.enrollments
      where class_id=p_class_id and student_id=v_student_id and status='active'
        and public.student_attends_class_on(v_student_id,p_class_id,p_date)
    ) then raise exception '이 날짜에 수강하지 않는 학생이 포함되어 있습니다.'; end if;

    if homework_status is null and homework_note is null then
      delete from public.lesson_homework_results
      where lesson_id=v_lesson_id and student_id=v_student_id;
    else
      insert into public.lesson_homework_results(lesson_id,student_id,status,note,created_by)
      values(v_lesson_id,v_student_id,homework_status,homework_note,auth.uid())
      on conflict(lesson_id,student_id) do update set
        status=excluded.status,note=excluded.note,updated_at=now();
    end if;
  end loop;
end $$;

create or replace function public.staff_class_attendance_calendar(p_class_id uuid,p_anchor_date date,p_view text default 'week')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare first_day date; last_day date; result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 출석 캘린더를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 출석 캘린더만 확인할 수 있습니다.'; end if;

  if p_view='month' then
    first_day:=date_trunc('month',p_anchor_date)::date;
    last_day:=(date_trunc('month',p_anchor_date)+interval '1 month - 1 day')::date;
  else
    first_day:=p_anchor_date-(extract(isodow from p_anchor_date)::integer-1);
    last_day:=first_day+6;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date',to_char(d.day::date,'YYYY-MM-DD'),
    'scheduled',exists(
      select 1 from public.class_schedules cs
      where cs.class_id=p_class_id and cs.weekday=extract(isodow from d.day::date)::smallint
        and (cs.valid_from is null or cs.valid_from<=d.day::date)
        and (cs.valid_until is null or cs.valid_until>=d.day::date)
    ),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'status',a.status) order by s.name)
      from public.lessons l
      join public.attendance a on a.lesson_id=l.id
      join public.students s on s.id=a.student_id
      where l.class_id=p_class_id and l.lesson_date=d.day::date
    ),'[]'::jsonb)
  ) order by d.day),'[]'::jsonb)
  into result
  from generate_series(first_day,last_day,interval '1 day') d(day);
  return result;
end $$;

revoke all on function public.staff_class_homework_results(uuid,date),public.staff_save_class_homework_results(uuid,date,jsonb),public.staff_class_attendance_calendar(uuid,date,text) from public;
grant execute on function public.staff_class_homework_results(uuid,date),public.staff_save_class_homework_results(uuid,date,jsonb),public.staff_class_attendance_calendar(uuid,date,text) to authenticated;

notify pgrst,'reload schema';
