-- Match the administrator-only save/apply API; direct table writes remain revoked.
create function public.admin_delete_timetable_plan(p_id uuid, p_version integer)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.timetable_plans;
begin
  if auth.uid() is null or public.current_user_role() is distinct from 'admin' then
    raise exception '관리자만 초안을 삭제할 수 있습니다.';
  end if;
  select * into r from public.timetable_plans where id = p_id for update;
  if not found then raise exception '이미 삭제된 초안입니다. 목록을 다시 불러와 주세요.'; end if;
  if r.applied_at is not null then raise exception '적용한 초안은 이력으로 보관되어 삭제할 수 없습니다.'; end if;
  if r.version is distinct from p_version then raise exception '다른 관리자가 수정한 초안입니다. 다시 불러온 뒤 삭제해 주세요.'; end if;
  delete from public.timetable_plans where id = r.id;
end $$;
revoke all on function public.admin_delete_timetable_plan(uuid, integer) from public, anon;
grant execute on function public.admin_delete_timetable_plan(uuid, integer) to authenticated;
