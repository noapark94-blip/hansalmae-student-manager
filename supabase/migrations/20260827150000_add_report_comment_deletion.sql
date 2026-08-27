-- 리포트 댓글 작성자별 삭제 권한
create or replace function public.family_report_comments(p_student_id uuid,p_lesson_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_view_family_report(p_student_id,p_lesson_id) then raise exception '확인할 수 없는 리포트입니다.'; end if;
  if public.current_user_role()<>'guardian' then return '[]'::jsonb; end if;
  update public.learning_report_comments set family_read_at=coalesce(family_read_at,now())
    where student_id=p_student_id and lesson_id=p_lesson_id and parent_id is not null;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'parentId',c.parent_id,
    'body',c.body,
    'authorName',p.display_name,
    'authorRole',p.role,
    'createdAt',c.created_at,
    'canDelete',c.author_profile_id=auth.uid() and c.parent_id is null
  ) order by c.created_at),'[]'::jsonb)
    into result from public.learning_report_comments c join public.profiles p on p.id=c.author_profile_id
    where c.student_id=p_student_id and c.lesson_id=p_lesson_id;
  return result;
end $$;

create or replace function public.staff_report_comments(p_student_id uuid,p_lesson_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_manage_family_report_comment(p_student_id,p_lesson_id) then raise exception '담당 리포트의 댓글만 확인할 수 있습니다.'; end if;
  update public.learning_report_comments set staff_read_at=coalesce(staff_read_at,now()) where student_id=p_student_id and lesson_id=p_lesson_id and parent_id is null;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'parentId',c.parent_id,
    'body',c.body,
    'authorName',p.display_name,
    'authorRole',p.role,
    'createdAt',c.created_at,
    'canDelete',public.current_user_role()='admin' or (c.author_profile_id=auth.uid() and c.parent_id is not null)
  ) order by c.created_at),'[]'::jsonb)
    into result from public.learning_report_comments c join public.profiles p on p.id=c.author_profile_id where c.student_id=p_student_id and c.lesson_id=p_lesson_id;
  return result;
end $$;

create or replace function public.delete_report_comment(p_comment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  target public.learning_report_comments;
  actor_role text;
  allowed boolean := false;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  select * into target from public.learning_report_comments where id=p_comment_id;
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
  delete from public.learning_report_comments where id=target.id;
end $$;

revoke all on function public.family_report_comments(uuid,uuid),public.staff_report_comments(uuid,uuid),public.delete_report_comment(uuid) from public,anon;
grant execute on function public.family_report_comments(uuid,uuid),public.staff_report_comments(uuid,uuid),public.delete_report_comment(uuid) to authenticated;
notify pgrst,'reload schema';
