create or replace function public.admin_permanently_delete_class(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.current_user_role()<>'admin' then
    raise exception '관리자만 클래스를 영구 삭제할 수 있습니다.';
  end if;
  if not exists(select 1 from public.classes where id=p_class_id) then
    raise exception '삭제할 클래스를 찾을 수 없습니다.';
  end if;
  delete from public.classes where id=p_class_id;
end
$$;

revoke all on function public.admin_permanently_delete_class(uuid) from public;
grant execute on function public.admin_permanently_delete_class(uuid) to authenticated;
notify pgrst,'reload schema';
