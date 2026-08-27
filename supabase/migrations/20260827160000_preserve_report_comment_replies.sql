-- 원댓글과 답변을 독립적으로 삭제하고 대화 맥락은 보존
alter table public.learning_report_comments add column if not exists deleted_at timestamptz;

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
    'body',case when c.deleted_at is null then c.body else '삭제된 댓글입니다.' end,
    'authorName',p.display_name,
    'authorRole',p.role,
    'createdAt',c.created_at,
    'canDelete',c.deleted_at is null and c.author_profile_id=auth.uid() and c.parent_id is null,
    'isDeleted',c.deleted_at is not null
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
  update public.learning_report_comments set staff_read_at=coalesce(staff_read_at,now()) where student_id=p_student_id and lesson_id=p_lesson_id and parent_id is null and deleted_at is null;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'parentId',c.parent_id,
    'body',case when c.deleted_at is null then c.body else '삭제된 댓글입니다.' end,
    'authorName',p.display_name,
    'authorRole',p.role,
    'createdAt',c.created_at,
    'canDelete',c.deleted_at is null and (public.current_user_role()='admin' or (c.author_profile_id=auth.uid() and c.parent_id is not null)),
    'isDeleted',c.deleted_at is not null
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
    delete from public.learning_report_comments where id=target.id;
  end if;
end $$;

revoke all on function public.family_report_comments(uuid,uuid),public.staff_report_comments(uuid,uuid),public.delete_report_comment(uuid) from public,anon;
grant execute on function public.family_report_comments(uuid,uuid),public.staff_report_comments(uuid,uuid),public.delete_report_comment(uuid) to authenticated;
notify pgrst,'reload schema';
