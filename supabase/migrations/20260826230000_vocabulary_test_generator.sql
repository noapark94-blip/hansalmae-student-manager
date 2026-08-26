create table if not exists public.vocabulary_word_sets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  sort_order integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.vocabulary_words (
  id bigint generated always as identity primary key,
  word_set_id uuid not null references public.vocabulary_word_sets(id) on delete cascade,
  day integer not null check (day > 0),
  word text not null,
  meaning text not null,
  example text not null default '',
  translation text not null default '',
  example_answer text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique (word_set_id, day, word, sort_order)
);

create index if not exists vocabulary_words_range_idx
  on public.vocabulary_words(word_set_id, day, sort_order);

create table if not exists public.vocabulary_test_history (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  word_set_id uuid references public.vocabulary_word_sets(id) on delete set null,
  word_set_name text not null,
  start_day integer not null,
  end_day integer not null,
  question_count integer not null check (question_count between 1 and 200),
  eng_to_kor_count integer not null default 0,
  kor_to_eng_count integer not null default 0,
  example_count integer not null default 0,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_by_name text not null,
  test_drive_url text,
  answer_drive_url text,
  created_at timestamptz not null default now()
);

create index if not exists vocabulary_test_history_created_idx
  on public.vocabulary_test_history(created_at desc);

alter table public.vocabulary_word_sets enable row level security;
alter table public.vocabulary_words enable row level security;
alter table public.vocabulary_test_history enable row level security;

grant select, insert, update, delete on public.vocabulary_word_sets to authenticated;
grant select, insert, update, delete on public.vocabulary_words to authenticated;
grant select, insert on public.vocabulary_test_history to authenticated;
grant usage, select on sequence public.vocabulary_words_id_seq to authenticated;

create policy "Staff can read vocabulary sets"
on public.vocabulary_word_sets for select to authenticated
using ((select public.current_user_role()) in ('admin','teacher','manager'));

create policy "Admins can insert vocabulary sets"
on public.vocabulary_word_sets for insert to authenticated
with check ((select public.current_user_role()) = 'admin');

create policy "Admins can update vocabulary sets"
on public.vocabulary_word_sets for update to authenticated
using ((select public.current_user_role()) = 'admin')
with check ((select public.current_user_role()) = 'admin');

create policy "Admins can delete vocabulary sets"
on public.vocabulary_word_sets for delete to authenticated
using ((select public.current_user_role()) = 'admin');

create policy "Staff can read vocabulary words"
on public.vocabulary_words for select to authenticated
using ((select public.current_user_role()) in ('admin','teacher','manager'));

create policy "Admins can insert vocabulary words"
on public.vocabulary_words for insert to authenticated
with check ((select public.current_user_role()) = 'admin');

create policy "Admins can update vocabulary words"
on public.vocabulary_words for update to authenticated
using ((select public.current_user_role()) = 'admin')
with check ((select public.current_user_role()) = 'admin');

create policy "Admins can delete vocabulary words"
on public.vocabulary_words for delete to authenticated
using ((select public.current_user_role()) = 'admin');

create policy "Staff can read vocabulary history"
on public.vocabulary_test_history for select to authenticated
using ((select public.current_user_role()) in ('admin','teacher','manager'));

create policy "Staff can create vocabulary history"
on public.vocabulary_test_history for insert to authenticated
with check (
  created_by = (select auth.uid())
  and (select public.current_user_role()) in ('admin','teacher','manager')
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
  if public.current_user_role() not in ('admin','teacher','manager') then
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

create or replace function public.cleanup_vocabulary_test_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.vocabulary_test_history
  where created_at < now() - interval '90 days';

  delete from public.vocabulary_test_history
  where id in (
    select id from public.vocabulary_test_history
    order by created_at desc, id desc
    offset 300
  );
  return new;
end;
$$;

revoke all on function public.cleanup_vocabulary_test_history() from public, anon, authenticated;

drop trigger if exists cleanup_vocabulary_test_history_after_insert on public.vocabulary_test_history;
create trigger cleanup_vocabulary_test_history_after_insert
after insert on public.vocabulary_test_history
for each statement execute function public.cleanup_vocabulary_test_history();

insert into public.vocabulary_word_sets(name,slug,sort_order)
values ('중등 영단어','middle',1),('고등 영단어','high',2),('수능 영단어','csat',3)
on conflict (slug) do update set name=excluded.name, sort_order=excluded.sort_order, enabled=true;
