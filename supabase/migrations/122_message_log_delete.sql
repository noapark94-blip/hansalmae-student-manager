-- 교직원이 문자 발송 내역을 개별 삭제할 수 있게 하되, 처리 중인 발송은 보호한다.
create or replace function public.staff_delete_message_log(p_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted boolean;
begin
  if not public.is_staff() then
    raise exception '교직원만 문자 내역을 삭제할 수 있습니다.';
  end if;

  delete from public.message_logs
  where id = p_message_id
    and status <> 'sending'
  returning true into deleted;

  return coalesce(deleted, false);
end
$$;

revoke all on function public.staff_delete_message_log(uuid) from public;
grant execute on function public.staff_delete_message_log(uuid) to authenticated;
