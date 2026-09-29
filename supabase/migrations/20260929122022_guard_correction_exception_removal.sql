-- Protect existing reports and validate the original slot before restoring it.
create or replace function public.staff_delete_correction_exception(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare e public.correction_schedule_exceptions; a public.correction_assignments; conflict_text text;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 첨삭 일정 변경을 삭제할 수 있습니다.'; end if;
 select * into e from public.correction_schedule_exceptions where id=p_id for update;
 if e.id is null then return; end if;
 select * into a from public.correction_assignments where id=e.assignment_id for update;
 -- Report writes cannot race the check/removal transaction.
 lock table public.correction_reports in share row exclusive mode;
 if e.kind in ('move','extra') and exists(select 1 from public.correction_reports r
   where r.assignment_id=e.assignment_id and r.correction_date=e.target_date and r.start_time=e.target_start_time) then
   raise exception '이 일정에 출결 또는 첨삭 기록이 있습니다. 기록을 확인한 뒤 기록 화면에서 삭제하고 다시 시도해 주세요.';
 end if;
 if e.kind in ('move','cancel') then
   if a.id is null or not a.active or a.valid_from>e.original_date or (a.valid_until is not null and a.valid_until<e.original_date)
     or a.weekday<>extract(isodow from e.original_date)::int then
     raise exception '고정 배정이 변경되거나 종료되었습니다. 현재 고정 일정을 먼저 확인해 주세요.';
   end if;
   select c.name||' 정규수업' into conflict_text
   from public.class_schedules cs join public.classes c on c.id=cs.class_id and c.active
   where cs.weekday=a.weekday and cs.start_time<a.end_time and cs.end_time>a.start_time
     and (cs.valid_from is null or cs.valid_from<=e.original_date) and (cs.valid_until is null or cs.valid_until>=e.original_date)
     and public.student_uses_class_schedule(a.student_id,cs.id)
     and public.student_attends_class_on(a.student_id,cs.class_id,e.original_date)
   limit 1;
   if conflict_text is not null then raise exception '원래 일정으로 복구할 수 없습니다: % 수업과 겹칩니다.',conflict_text; end if;
   if exists(select 1 from public.correction_assignments other where other.id<>a.id and other.student_id=a.student_id
      and other.active and other.weekday=a.weekday and other.valid_from<=e.original_date and (other.valid_until is null or other.valid_until>=e.original_date)
      and other.start_time<a.end_time and other.end_time>a.start_time
      and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=other.id and x.original_date=e.original_date and x.kind in ('move','cancel')))
    or exists(select 1 from public.correction_schedule_exceptions x join public.correction_assignments other on other.id=x.assignment_id
      where x.id<>e.id and other.student_id=a.student_id and x.kind in ('move','extra') and x.target_date=e.original_date
      and x.target_start_time<a.end_time and x.target_end_time>a.start_time) then
      raise exception '원래 일정으로 복구할 수 없습니다: 다른 첨삭 일정과 겹칩니다.';
   end if;
   if exists(select 1 from public.teacher_special_lessons l join public.teacher_special_lesson_students s on s.session_id=l.id
      where s.student_id=a.student_id and l.lesson_date=e.original_date and l.starts_at<a.end_time and l.ends_at>a.start_time) then
      raise exception '원래 일정으로 복구할 수 없습니다: 보강·추가수업과 겹칩니다.';
   end if;
 end if;
 delete from public.correction_schedule_exceptions where id=p_id;
end $$;
revoke all on function public.staff_delete_correction_exception(uuid) from public,anon;
grant execute on function public.staff_delete_correction_exception(uuid) to authenticated;
