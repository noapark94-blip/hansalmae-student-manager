create or replace function public.check_account_invite(p_code_hash bytea)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare invitation public.account_invites%rowtype;
begin
  select * into invitation from public.account_invites where code_hash=p_code_hash;
  if invitation.id is null or invitation.used_at is not null or invitation.revoked_at is not null or invitation.expires_at<=now() then
    return null;
  end if;
  return jsonb_build_object('id',invitation.id,'role',invitation.role,'targetName',coalesce((select name from public.students where id=invitation.student_id),'선생님 계정'));
end
$$;
revoke all on function public.check_account_invite(bytea) from public;
grant execute on function public.check_account_invite(bytea) to service_role;
