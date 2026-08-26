alter policy "Staff can read vocabulary sets"
on public.vocabulary_word_sets
using ((select public.current_user_role()) in ('admin','teacher','assistant','manager'));

alter policy "Staff can read vocabulary words"
on public.vocabulary_words
using ((select public.current_user_role()) in ('admin','teacher','assistant','manager'));

alter policy "Staff can read vocabulary history"
on public.vocabulary_test_history
using ((select public.current_user_role()) in ('admin','teacher','assistant','manager'));

alter policy "Staff can create vocabulary history"
on public.vocabulary_test_history
with check (
  created_by = (select auth.uid())
  and (select public.current_user_role()) in ('admin','teacher','assistant','manager')
);

create or replace function public.staff_get_vocabulary_words(
  p_word_set_id uuid,
  p_start_day integer,
  p_end_day integer
)
returns table (
  id bigint,
  day integer,
  word text,
  meaning text,
  example text,
  translation text,
  example_answer text,
  sort_order integer
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if public.current_user_role() not in ('admin','teacher','assistant','manager') then
    raise exception '교직원만 단어 시험을 출제할 수 있습니다.';
  end if;
  if p_start_day < 1 or p_end_day < p_start_day then
    raise exception 'Day 범위가 올바르지 않습니다.';
  end if;
  return query
  select w.id,w.day,w.word,w.meaning,w.example,w.translation,w.example_answer,w.sort_order
  from public.vocabulary_words w
  where w.word_set_id = p_word_set_id
    and w.day between p_start_day and p_end_day
  order by w.day,w.sort_order,w.id;
end;
$$;

revoke all on function public.staff_get_vocabulary_words(uuid,integer,integer) from public;
grant execute on function public.staff_get_vocabulary_words(uuid,integer,integer) to authenticated;
