-- 정원 설정 기능 완전 제거: 기존 공식 첨삭 시간표의 주별 변경에서도 정원 검사를 하지 않습니다.

create or replace function public.prevent_correction_exception_conflict()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  target_student uuid;
begin
  select ca.student_id into target_student
  from public.correction_assignments ca
  where ca.id=new.assignment_id;

  if target_student is null then
    raise exception '고정 첨삭 배정을 찾을 수 없습니다.';
  end if;

  -- 같은 학생이 같은 주/같은 슬롯에 중복되는 경우만 막습니다. 인원 정원은 검사하지 않습니다.
  if exists(
    select 1
    from public.correction_exceptions ce
    join public.correction_assignments ca on ca.id=ce.assignment_id
    where ce.id<>new.id
      and ce.week_start=new.week_start
      and ce.weekday=new.weekday
      and ce.slot_index=new.slot_index
      and ca.student_id=target_student
  ) or exists(
    select 1
    from public.correction_assignments ca
    where ca.id<>new.assignment_id
      and ca.student_id=target_student
      and ca.weekday=new.weekday
      and ca.slot_index=new.slot_index
      and (ca.valid_until is null or ca.valid_until>=new.week_start)
      and not exists(
        select 1 from public.correction_exceptions moved
        where moved.assignment_id=ca.id and moved.week_start=new.week_start
      )
  ) then
    raise exception '학생에게 변경하려는 주의 같은 첨삭 시간이 이미 있습니다.';
  end if;

  return new;
end $$;

-- 정원 테이블은 과거 데이터 보존을 위해 남기되 앱/트리거에서 더 이상 사용하지 않습니다.
notify pgrst,'reload schema';
