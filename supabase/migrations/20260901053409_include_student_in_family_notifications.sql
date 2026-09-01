-- 알림에서 관련 자녀를 식별해 앱 전체 자녀 선택을 자동 전환합니다.

create or replace function public.family_notification_center()
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  perform public.sync_family_announcement_notifications();
  select jsonb_build_object(
    'unreadCount',count(*) filter(where n.read_at is null),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',n.id,'studentId',n.student_id,'studentName',s.name,'eventKey',n.event_key,
      'title',n.title,'body',n.body,'sourceType',n.source_type,'sourceId',n.source_id,
      'readAt',n.read_at,'createdAt',n.created_at
    ) order by n.created_at desc),'[]'::jsonb)
  ) into result
  from (select * from public.family_notifications where recipient_profile_id=auth.uid() order by created_at desc limit 50) n
  join public.students s on s.id=n.student_id;
  return result;
end;
$$;

revoke all on function public.family_notification_center() from public;
grant execute on function public.family_notification_center() to authenticated;
notify pgrst,'reload schema';
