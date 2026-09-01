-- 클래스 요일은 앱 전체에서 월=1 ... 일=7을 사용합니다.
-- 초기 스키마에 남아 있던 0...6 제약을 현재 기준과 일치시킵니다.

alter table public.class_schedules
  drop constraint if exists class_schedules_weekday_check;

-- 과거 일요일을 0으로 저장한 데이터가 있다면 현재 기준으로 보정합니다.
update public.class_schedules
set weekday = 7
where weekday = 0;

alter table public.class_schedules
  add constraint class_schedules_weekday_check
  check (weekday between 1 and 7);
