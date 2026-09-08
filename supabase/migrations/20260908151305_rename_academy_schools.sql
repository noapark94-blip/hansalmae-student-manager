create or replace function public.staff_rename_school(p_school_id uuid, p_name text)
returns void language plpgsql security definer set search_path=public as $$
declare
  old_name text;
  clean_name text := trim(p_name);
begin
  if not public.is_staff() then raise exception '교직원만 학교 이름을 수정할 수 있습니다.'; end if;
  if clean_name = '' then raise exception '학교 이름을 입력해 주세요.'; end if;

  select name into old_name
  from public.academy_schools
  where id = p_school_id and active
  for update;
  if old_name is null then raise exception '학교를 찾을 수 없습니다.'; end if;

  if exists(
    select 1 from public.academy_schools
    where id <> p_school_id
      and active
      and lower(regexp_replace(name, '[[:space:]]+', '', 'g')) = lower(regexp_replace(clean_name, '[[:space:]]+', '', 'g'))
  ) then raise exception '이미 등록된 학교 이름입니다.'; end if;

  update public.academy_schools set name = clean_name where id = p_school_id;
  update public.students set school = clean_name
    where lower(regexp_replace(coalesce(school, ''), '[[:space:]]+', '', 'g')) = lower(regexp_replace(old_name, '[[:space:]]+', '', 'g'));
  update public.academic_calendar_events set school = clean_name, updated_at = now()
    where lower(regexp_replace(coalesce(school, ''), '[[:space:]]+', '', 'g')) = lower(regexp_replace(old_name, '[[:space:]]+', '', 'g'));
end $$;

revoke all on function public.staff_rename_school(uuid,text) from public,anon;
grant execute on function public.staff_rename_school(uuid,text) to authenticated;
notify pgrst,'reload schema';
