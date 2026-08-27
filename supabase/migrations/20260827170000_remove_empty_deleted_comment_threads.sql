-- 양쪽 글이 모두 삭제되면 빈 댓글 대화 전체를 정리
create or replace function public.delete_report_comment(p_comment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  target public.learning_report_comments;
  actor_role text;
  allowed boolean := false;
  root_id uuid;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  select * into target from public.learning_report_comments where id=p_comment_id and deleted_at is null;
  if target.id is null then raise exception '삭제할 댓글을 찾을 수 없습니다.'; end if;

  actor_role:=public.current_user_role();
  if actor_role='admin' then
    allowed:=true;
  elsif target.author_profile_id=auth.uid() and actor_role='guardian' and target.parent_id is null then
    allowed:=public.can_view_family_report(target.student_id,target.lesson_id);
  elsif target.author_profile_id=auth.uid() and actor_role in ('teacher','manager') and target.parent_id is not null then
    allowed:=public.can_manage_family_report_comment(target.student_id,target.lesson_id);
  end if;

  if not allowed then raise exception '이 댓글을 삭제할 권한이 없습니다.'; end if;

  if target.parent_id is null and exists(select 1 from public.learning_report_comments where parent_id=target.id) then
    update public.learning_report_comments set body='삭제된 댓글입니다.',deleted_at=now() where id=target.id;
  else
    root_id:=target.parent_id;
    delete from public.learning_report_comments where id=target.id;
    if root_id is not null
      and exists(select 1 from public.learning_report_comments where id=root_id and deleted_at is not null)
      and not exists(select 1 from public.learning_report_comments where parent_id=root_id)
    then
      delete from public.learning_report_comments where id=root_id;
    end if;
  end if;
end $$;

revoke all on function public.delete_report_comment(uuid) from public,anon;
grant execute on function public.delete_report_comment(uuid) to authenticated;
notify pgrst,'reload schema';
