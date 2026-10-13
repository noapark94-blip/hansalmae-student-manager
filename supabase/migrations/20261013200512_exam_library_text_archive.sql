create table public.exam_library_exams (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references public.profiles(id),
 title text not null check (length(trim(title)) between 1 and 200),
 subject text not null check (subject in ('국어','영어','수학')),
 school text not null check (length(trim(school)) between 1 and 80),
 grade text not null check (grade in ('중1','중2','중3','고1','고2','고3')),
 year integer not null check (year between 2000 and 2100),
 term text not null check (term in ('1학기','2학기')),
 exam_kind text not null check (exam_kind in ('중간고사','기말고사','모의고사','기타')),
 description text not null default '' check (length(description)<=2000),
 questions jsonb not null check (jsonb_typeof(questions)='array' and jsonb_array_length(questions) between 1 and 200 and octet_length(questions::text)<=2000000),
 version bigint not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
alter table public.exam_library_exams enable row level security;
revoke all on public.exam_library_exams from anon,authenticated;
grant select,delete on public.exam_library_exams to authenticated;
grant insert(title,subject,school,grade,year,term,exam_kind,description,questions) on public.exam_library_exams to authenticated;
grant update(title,subject,school,grade,year,term,exam_kind,description,questions) on public.exam_library_exams to authenticated;
create policy exam_library_read on public.exam_library_exams for select to authenticated
 using ((select public.current_user_role()) in ('admin','sub_admin','teacher'));
create policy exam_library_insert on public.exam_library_exams for insert to authenticated
 with check ((select public.current_user_role()) in ('admin','sub_admin','teacher') and owner_id=(select auth.uid()));
create policy exam_library_update on public.exam_library_exams for update to authenticated
 using ((select public.current_user_role())='admin' or ((select public.current_user_role()) in ('sub_admin','teacher') and owner_id=(select auth.uid())))
 with check ((select public.current_user_role())='admin' or ((select public.current_user_role()) in ('sub_admin','teacher') and owner_id=(select auth.uid())));
create policy exam_library_delete on public.exam_library_exams for delete to authenticated
 using ((select public.current_user_role())='admin' or ((select public.current_user_role()) in ('sub_admin','teacher') and owner_id=(select auth.uid())));
create index exam_library_filters on public.exam_library_exams(subject,school,grade,year desc);
create index exam_library_updated on public.exam_library_exams(updated_at desc);
create function public.exam_library_validate() returns trigger language plpgsql security invoker set search_path=public as $$
declare q jsonb; field text; seen_ids text[]:='{}';
begin
 for q in select value from jsonb_array_elements(new.questions) loop
  if jsonb_typeof(q)<>'object' then raise exception '문항 형식을 확인해 주세요.'; end if;
  foreach field in array array['id','number','passage','prompt','choices','answer','explanation','diagram'] loop
   if coalesce(jsonb_typeof(q->field),'')<>'string' then raise exception '문항 항목을 확인해 주세요.'; end if;
  end loop;
  if length(q->>'id') not between 1 and 80 or q->>'id'=any(seen_ids) then raise exception '문항 번호가 중복되었습니다.'; end if;
  seen_ids:=array_append(seen_ids,q->>'id');
  if trim(q->>'passage')='' and trim(q->>'prompt')='' then raise exception '빈 문항은 저장할 수 없습니다.'; end if;
  if length(q->>'diagram')>450000 or ((q->>'diagram')<>'' and (q->>'diagram')!~'^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$') then raise exception '도형 이미지를 확인해 주세요.'; end if;
 end loop;
 if tg_op='UPDATE' then new.version:=old.version+1;new.updated_at:=clock_timestamp();end if;
 return new;
end $$;
revoke all on function public.exam_library_validate() from public,anon,authenticated;
create trigger exam_library_validate before insert or update on public.exam_library_exams for each row execute function public.exam_library_validate();
create function public.exam_library_list(p_subject text default null,p_school text default null,p_grade text default null,p_year integer default null,p_term text default null,p_kind text default null,p_query text default null,p_offset integer default 0)
returns jsonb language sql stable security invoker set search_path=public as $$
 with filtered as (
  select * from public.exam_library_exams e where (p_subject is null or e.subject=p_subject) and (p_school is null or e.school=p_school)
   and (p_grade is null or e.grade=p_grade) and (p_year is null or e.year=p_year) and (p_term is null or e.term=p_term) and (p_kind is null or e.exam_kind=p_kind)
   and (nullif(trim(p_query),'') is null or position(lower(p_query) in lower(e.title||' '||e.school||' '||e.description))>0
    or exists(select 1 from jsonb_array_elements(e.questions) q where position(lower(p_query) in lower(coalesce(q->>'passage','')||' '||coalesce(q->>'prompt','')||' '||coalesce(q->>'choices','')))>0))
 ), paged as (select * from filtered order by updated_at desc,id limit 20 offset greatest(0,least(coalesce(p_offset,0),100000)))
 select jsonb_build_object('items',coalesce((select jsonb_agg((to_jsonb(p)-'questions')||jsonb_build_object('question_count',jsonb_array_length(p.questions),'content_bytes',octet_length(p.questions::text)) order by p.updated_at desc,p.id) from paged p),'[]'::jsonb),'total',(select count(*) from filtered),'schools',coalesce((select jsonb_agg(s.school order by s.school) from (select distinct school from public.exam_library_exams) s),'[]'::jsonb));
$$;
revoke all on function public.exam_library_list(text,text,text,integer,text,text,text,integer) from public,anon;
grant execute on function public.exam_library_list(text,text,text,integer,text,text,text,integer) to authenticated;
notify pgrst,'reload schema';
