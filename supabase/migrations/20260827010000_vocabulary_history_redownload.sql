alter table public.vocabulary_test_history
  add column if not exists question_snapshot jsonb;

alter table public.vocabulary_test_history
  drop constraint if exists vocabulary_test_history_snapshot_array;

alter table public.vocabulary_test_history
  add constraint vocabulary_test_history_snapshot_array
  check (question_snapshot is null or jsonb_typeof(question_snapshot) = 'array');

create or replace function public.cleanup_vocabulary_test_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.vocabulary_test_history
  where created_at < now() - interval '30 days';

  delete from public.vocabulary_test_history
  where id in (
    select id from public.vocabulary_test_history
    order by created_at desc, id desc
    offset 100
  );
  return new;
end;
$$;

revoke all on function public.cleanup_vocabulary_test_history() from public, anon, authenticated;

delete from public.vocabulary_test_history
where created_at < now() - interval '30 days';

delete from public.vocabulary_test_history
where id in (
  select id from public.vocabulary_test_history
  order by created_at desc, id desc
  offset 100
);
