create index if not exists student_schedule_assignments_schedule_student_idx
  on public.student_schedule_assignments(class_schedule_id, student_id);

create or replace function public.staff_class_student_schedule_choices(p_class_id uuid,p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수강 요일을 확인할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers
    where class_id=p_class_id and profile_id=auth.uid()
  ) then
    raise exception '담당 클래스의 수강 요일만 설정할 수 있습니다.';
  end if;
  if not exists(
    select 1 from public.enrollments
    where class_id=p_class_id and student_id=p_student_id and status='active'
  ) then
    raise exception '현재 이 클래스를 수강 중인 학생이 아닙니다.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'scheduleId',cs.id,
    'weekday',cs.weekday,
    'startTime',cs.start_time,
    'endTime',cs.end_time,
    'assigned',case
      when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
        then exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id=p_student_id and ssa.class_schedule_id=cs.id)
      else true
    end
  ) order by cs.weekday,cs.start_time),'[]'::jsonb) into result
  from public.class_schedules cs
  where cs.class_id=p_class_id
    and (cs.valid_from is null or cs.valid_from<=current_date)
    and (cs.valid_until is null or cs.valid_until>=current_date);
  return result;
end $$;

create or replace function public.staff_save_class_student_schedule_assignments(p_class_id uuid,p_student_id uuid,p_schedule_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]);
begin
  if not public.is_staff() then
    raise exception '교직원만 수강 요일을 저장할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers
    where class_id=p_class_id and profile_id=auth.uid()
  ) then
    raise exception '담당 클래스의 수강 요일만 설정할 수 있습니다.';
  end if;
  if not exists(
    select 1 from public.enrollments
    where class_id=p_class_id and student_id=p_student_id and status='active'
  ) then
    raise exception '현재 이 클래스를 수강 중인 학생이 아닙니다.';
  end if;
  if cardinality(requested)=0 then
    raise exception '최소 한 개의 수업 요일·시간을 선택해 주세요.';
  end if;
  if cardinality(requested)<>(select count(distinct id) from unnest(requested) id) then
    raise exception '중복된 수업 시간이 포함되어 있습니다.';
  end if;
  if exists(
    select 1 from unnest(requested) requested_id
    where not exists(
      select 1 from public.class_schedules cs
      where cs.id=requested_id and cs.class_id=p_class_id
        and (cs.valid_from is null or cs.valid_from<=current_date)
        and (cs.valid_until is null or cs.valid_until>=current_date)
    )
  ) then
    raise exception '현재 이 클래스에 등록된 수업 시간만 선택할 수 있습니다.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));

  -- 첫 개인 배정을 만들 때 다른 클래스는 기존처럼 전체 요일을 유지합니다.
  if not exists(select 1 from public.student_schedule_assignments where student_id=p_student_id) then
    insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
    select p_student_id,cs.id,auth.uid()
    from public.enrollments e
    join public.classes c on c.id=e.class_id and c.active
    join public.class_schedules cs on cs.class_id=c.id
    where e.student_id=p_student_id and e.status='active'
      and (cs.valid_from is null or cs.valid_from<=current_date)
      and (cs.valid_until is null or cs.valid_until>=current_date)
    on conflict do nothing;
  end if;

  delete from public.student_schedule_assignments ssa
  using public.class_schedules cs
  where ssa.class_schedule_id=cs.id
    and ssa.student_id=p_student_id
    and cs.class_id=p_class_id;

  insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
  select p_student_id,id,auth.uid() from unnest(requested) id
  on conflict do nothing;
end $$;

revoke all on function public.staff_class_student_schedule_choices(uuid,uuid),public.staff_save_class_student_schedule_assignments(uuid,uuid,uuid[]) from public;
grant execute on function public.staff_class_student_schedule_choices(uuid,uuid),public.staff_save_class_student_schedule_assignments(uuid,uuid,uuid[]) to authenticated;
notify pgrst,'reload schema';
