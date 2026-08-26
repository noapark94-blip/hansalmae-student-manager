-- 과거 첨삭 명단에서 누락된 학생을 정규 배정 기간과 분리해 해당 날짜에만 추가합니다.

create or replace function public.staff_add_correction_date_assignment(
  p_date date,p_student_id uuid,p_subject text,p_start_time time,p_end_time time,
  p_tutor_profile_id uuid,p_supervisor_profile_id uuid,p_note text
) returns uuid language plpgsql security definer set search_path=public as $$
declare result uuid;v_weekday smallint:=extract(isodow from p_date)::smallint;legacy_teacher uuid:=coalesce(p_tutor_profile_id,auth.uid());
begin
  if not public.is_staff() then raise exception '교직원만 과거 첨삭 명단을 보정할 수 있습니다.'; end if;
  if p_date is null or p_date>=(timezone('Asia/Seoul',now()))::date then raise exception '지난 날짜만 누락 학생을 추가할 수 있습니다.'; end if;
  if p_subject not in ('국어','영어','수학') then raise exception '첨삭 과목을 확인해 주세요.'; end if;
  if p_start_time>=p_end_time then raise exception '첨삭 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then raise exception '재원 학생을 선택해 주세요.'; end if;
  if exists(
    select 1 from public.correction_assignments a
    where a.student_id=p_student_id and a.subject=p_subject and a.weekday=v_weekday and a.start_time=p_start_time
      and a.valid_from<=p_date and (a.valid_until is null or a.valid_until>=p_date)
  ) then raise exception '이 학생은 선택한 날짜와 시간에 이미 포함되어 있습니다.'; end if;
  insert into public.correction_assignments(
    student_id,teacher_profile_id,weekday,slot_index,valid_from,valid_until,subject,start_time,end_time,
    tutor_profile_id,supervisor_profile_id,note,active,created_by,updated_at
  ) values(
    p_student_id,legacy_teacher,v_weekday,null,p_date,p_date,p_subject,p_start_time,p_end_time,
    p_tutor_profile_id,p_supervisor_profile_id,nullif(trim(p_note),''),false,auth.uid(),now()
  ) returning id into result;
  return result;
end $$;

revoke all on function public.staff_add_correction_date_assignment(date,uuid,text,time,time,uuid,uuid,text) from public,anon;
grant execute on function public.staff_add_correction_date_assignment(date,uuid,text,time,time,uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';
