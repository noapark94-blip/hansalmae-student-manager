-- 클래스 기본 정보와 여러 요일·시간을 한 트랜잭션에서 수정합니다.
-- PostgreSQL은 timestamptz를 UTC로 안전하게 보관하고, 업무 날짜 계산은 서울 시간으로 수행합니다.

alter database postgres set timezone to 'Asia/Seoul';

create or replace function public.staff_class_management_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 클래스 목록을 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'subject',c.subject,'subjectId',c.subject_id,'room',c.room,'color',c.color,'active',c.active,
    'schedules',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time) order by cs.weekday,cs.start_time) from public.class_schedules cs where cs.class_id=c.id and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
    'enrollmentCount',(select count(*) from public.enrollments e where e.class_id=c.id),
    'scheduleCount',(select count(*) from public.class_schedules cs where cs.class_id=c.id),
    'lessonCount',(select count(*) from public.lessons l where l.class_id=c.id),
    'assignmentCount',(select count(*) from public.assignments a where a.class_id=c.id)
  ) order by c.active desc,c.subject,c.name)
  from public.classes c
  where public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid())),'[]'::jsonb);
end $$;

create or replace function public.staff_update_class_with_schedules(
  p_class_id uuid,
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  schedule_row jsonb;
  teacher_ids uuid[];
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception '수업 요일과 시간을 한 개 이상 입력해 주세요.';
  end if;

  select array_agg(profile_id order by profile_id) into teacher_ids from public.class_teachers where class_id=p_class_id;
  if coalesce(array_length(teacher_ids,1),0)=0 then teacher_ids:=array[auth.uid()]::uuid[]; end if;

  perform public.staff_update_class(p_class_id,p_name,p_subject_id,p_room,p_color);
  delete from public.class_schedules where class_id=p_class_id;

  for schedule_row in select value from jsonb_array_elements(p_schedules)
  loop
    perform public.staff_save_class_schedule(
      null,
      p_class_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time,
      teacher_ids
    );
  end loop;
end
$$;

revoke all on function public.staff_update_class_with_schedules(uuid,text,uuid,text,text,jsonb) from public;
grant execute on function public.staff_update_class_with_schedules(uuid,text,uuid,text,text,jsonb) to authenticated;
revoke all on function public.staff_class_management_board() from public;
grant execute on function public.staff_class_management_board() to authenticated;
notify pgrst,'reload schema';
