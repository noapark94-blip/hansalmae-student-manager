-- 규칙 적용 전에 양쪽 모두 삭제되어 남은 빈 대화를 정리
delete from public.learning_report_comments root
where root.parent_id is null
  and root.deleted_at is not null
  and not exists(
    select 1 from public.learning_report_comments reply
    where reply.parent_id=root.id
  );

notify pgrst,'reload schema';
