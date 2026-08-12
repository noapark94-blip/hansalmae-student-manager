create table if not exists public.academy_schools (
  id uuid primary key default gen_random_uuid(), name text not null,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists academy_schools_normalized_name_key on public.academy_schools (lower(regexp_replace(name, '[[:space:]]+', '', 'g')));
insert into public.academy_schools (name) select distinct trim(school) from public.students where nullif(trim(school), '') is not null on conflict do nothing;
alter table public.academy_schools enable row level security;
drop policy if exists "staff_read_academy_schools" on public.academy_schools;
drop policy if exists "staff_manage_academy_schools" on public.academy_schools;
create policy "staff_read_academy_schools" on public.academy_schools for select to authenticated using (public.is_staff());
create policy "staff_manage_academy_schools" on public.academy_schools for all to authenticated using (public.is_staff()) with check (public.is_staff());
grant select, insert, update on public.academy_schools to authenticated;

create or replace function public.staff_registration_schools() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name) order by name), '[]'::jsonb) from public.academy_schools where active;
$$;
create or replace function public.staff_create_school(p_name text) returns uuid language plpgsql security definer set search_path = public as $$
declare clean_name text := trim(p_name); school_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 학교를 추가할 수 있습니다.'; end if;
  if clean_name = '' then raise exception '학교 이름을 입력해 주세요.'; end if;
  select id into school_id from public.academy_schools where lower(regexp_replace(name, '[[:space:]]+', '', 'g')) = lower(regexp_replace(clean_name, '[[:space:]]+', '', 'g'));
  if school_id is not null then update public.academy_schools set active = true where id = school_id; return school_id; end if;
  insert into public.academy_schools(name, created_by) values (clean_name, auth.uid()) returning id into school_id;
  return school_id;
end;
$$;
revoke all on function public.staff_registration_schools() from public;
revoke all on function public.staff_create_school(text) from public;
grant execute on function public.staff_registration_schools() to authenticated;
grant execute on function public.staff_create_school(text) to authenticated;
