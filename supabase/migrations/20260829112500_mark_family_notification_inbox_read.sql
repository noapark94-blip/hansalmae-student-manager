-- Opening the family notification drawer counts as reviewing the visible inbox.

create or replace function public.mark_family_notification_inbox_read()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  marked integer:=0;
  affected integer:=0;
begin
  if auth.uid() is null or public.current_user_role() not in ('guardian','student') then
    raise exception '학생·학부모 알림함에서만 사용할 수 있습니다.';
  end if;

  update public.family_notifications
  set read_at=coalesce(read_at,now())
  where recipient_profile_id=auth.uid() and read_at is null;
  get diagnostics marked=row_count;

  if public.current_user_role()='guardian' then
    update public.learning_report_comments reply
    set family_read_at=coalesce(reply.family_read_at,now())
    from public.learning_report_comments root_comment
    where root_comment.id=reply.parent_id
      and root_comment.author_profile_id=auth.uid()
      and reply.family_read_at is null;
    get diagnostics affected=row_count;
    marked:=marked+affected;
  end if;

  return marked;
end;
$$;

revoke all on function public.mark_family_notification_inbox_read() from public,anon;
grant execute on function public.mark_family_notification_inbox_read() to authenticated;

notify pgrst,'reload schema';
