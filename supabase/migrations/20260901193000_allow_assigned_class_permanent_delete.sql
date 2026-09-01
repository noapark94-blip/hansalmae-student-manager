-- 관리자는 모든 클래스를, 선생님과 실장님은 본인이 담당하는 클래스만
-- 영구 삭제할 수 있습니다. 화면 노출과 무관하게 서버에서 다시 검증합니다.

create or replace function public.admin_permanently_delete_class(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  actor_role public.user_role;
begin
  actor_role := public.current_user_role();

  if actor_role = 'admin' then
    null;
  elsif actor_role in ('teacher', 'manager')
    and public.is_staff()
    and exists (
      select 1
      from public.class_teachers
      where class_id = p_class_id
        and profile_id = auth.uid()
    ) then
    null;
  else
    raise exception '관리자 또는 담당 선생님만 클래스를 영구 삭제할 수 있습니다.';
  end if;

  if not exists(select 1 from public.classes where id=p_class_id) then
    raise exception '삭제할 클래스를 찾을 수 없습니다.';
  end if;

  delete from public.classes where id=p_class_id;
end
$$;

revoke all on function public.admin_permanently_delete_class(uuid) from public, anon;
grant execute on function public.admin_permanently_delete_class(uuid) to authenticated;

notify pgrst,'reload schema';
