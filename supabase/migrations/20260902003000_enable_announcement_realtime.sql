-- 학부모 홈이 반복 조회 대신 공지 변경 신호를 실시간으로 받을 수 있게 합니다.

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='announcements') then
    alter publication supabase_realtime add table public.announcements;
  end if;
end $$;
