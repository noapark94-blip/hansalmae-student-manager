-- 댓글 알림에서 담당 수업 기록 화면으로 안전하게 이동하기 위한 최소 조회 함수입니다.
create or replace function public.staff_report_comment_lesson_target(p_student_id uuid, p_lesson_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  target jsonb;
begin
  if auth.uid() is null or not public.can_manage_family_report_comment(p_student_id, p_lesson_id) then
    raise exception '담당 수업만 확인할 수 있습니다.';
  end if;

  select jsonb_build_object(
    'classId', l.class_id,
    'lessonDate', l.lesson_date
  )
  into target
  from public.lessons l
  where l.id = p_lesson_id;

  if target is null then
    raise exception '연결된 수업 기록을 찾지 못했습니다.';
  end if;
  return target;
end;
$$;

revoke all on function public.staff_report_comment_lesson_target(uuid,uuid) from public, anon;
grant execute on function public.staff_report_comment_lesson_target(uuid,uuid) to authenticated;

notify pgrst, 'reload schema';
