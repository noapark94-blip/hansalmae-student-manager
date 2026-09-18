create or replace function public.staff_archive_subject(p_subject_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare subject_row public.academy_subjects%rowtype;
begin
  if not coalesce(public.is_staff(),false) then
    raise exception '교직원만 과목을 삭제할 수 있습니다.';
  end if;
  select * into subject_row from public.academy_subjects where id=p_subject_id for update;
  if not found then raise exception '과목을 찾을 수 없습니다.'; end if;
  if subject_row.parent_id is null or subject_row.name=subject_row.main_subject then
    raise exception '기본 과목은 삭제할 수 없습니다.';
  end if;
  update public.academy_subjects set active=false where id=p_subject_id;
end $$;
revoke all on function public.staff_archive_subject(uuid) from public,anon;
grant execute on function public.staff_archive_subject(uuid) to authenticated;
