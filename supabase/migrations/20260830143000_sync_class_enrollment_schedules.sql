-- 개인 시간표를 사용하는 학생을 새 클래스에 추가할 때 해당 클래스의
-- 정규 시간표도 함께 연결하여 수업 기록 명단에서 누락되지 않게 합니다.
create or replace function public.staff_set_class_enrollment(
  p_class_id uuid,
  p_student_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uses_personal_schedule boolean;
begin
  if not public.is_staff() then
    raise exception '교직원만 클래스 학생을 변경할 수 있습니다.';
  end if;

  if public.current_user_role() <> 'admin'
    and not exists (
      select 1
      from public.class_teachers
      where class_id = p_class_id
        and profile_id = auth.uid()
    ) then
    raise exception '담당 클래스의 학생만 변경할 수 있습니다.';
  end if;

  select exists (
    select 1
    from public.student_schedule_assignments
    where student_id = p_student_id
  )
  into v_uses_personal_schedule;

  if p_active then
    update public.enrollments
    set status = 'active', ended_on = null
    where student_id = p_student_id
      and class_id = p_class_id
      and status <> 'active';

    if not found then
      insert into public.enrollments(student_id, class_id, status, started_on)
      values (p_student_id, p_class_id, 'active', current_date);
    end if;

    -- 개인 시간표가 이미 있는 학생만 명시 배정을 확장합니다.
    -- 개인 시간표를 사용하지 않는 학생은 기존처럼 활성 수강반 전체가 적용됩니다.
    if v_uses_personal_schedule then
      insert into public.student_schedule_assignments(
        student_id,
        class_schedule_id,
        assigned_by
      )
      select p_student_id, cs.id, auth.uid()
      from public.class_schedules cs
      where cs.class_id = p_class_id
      on conflict (student_id, class_schedule_id) do nothing;
    end if;
  else
    update public.enrollments
    set status = 'completed', ended_on = current_date
    where student_id = p_student_id
      and class_id = p_class_id
      and status = 'active';

    if v_uses_personal_schedule then
      delete from public.student_schedule_assignments ssa
      using public.class_schedules cs
      where ssa.student_id = p_student_id
        and ssa.class_schedule_id = cs.id
        and cs.class_id = p_class_id;
    end if;
  end if;
end;
$$;

revoke all on function public.staff_set_class_enrollment(uuid, uuid, boolean)
from public, anon;
grant execute on function public.staff_set_class_enrollment(uuid, uuid, boolean)
to authenticated;

-- 기존 활성 수강 중 개인 시간표에 빠진 반도 일괄 복구합니다.
insert into public.student_schedule_assignments(
  student_id,
  class_schedule_id,
  assigned_by
)
select distinct e.student_id, cs.id, null::uuid
from public.enrollments e
join public.class_schedules cs on cs.class_id = e.class_id
where e.status = 'active'
  and exists (
    select 1
    from public.student_schedule_assignments existing
    where existing.student_id = e.student_id
  )
  and not exists (
    select 1
    from public.student_schedule_assignments same_class
    join public.class_schedules same_schedule
      on same_schedule.id = same_class.class_schedule_id
    where same_class.student_id = e.student_id
      and same_schedule.class_id = e.class_id
  )
on conflict (student_id, class_schedule_id) do nothing;

notify pgrst, 'reload schema';
