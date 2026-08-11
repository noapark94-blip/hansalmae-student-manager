-- 로그인한 사용자가 자신의 표시 이름과 연락처만 안전하게 변경할 수 있게 합니다.

create or replace function public.save_my_account(p_display_name text, p_phone text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare my_role public.user_role;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if nullif(trim(p_display_name), '') is null then raise exception '표시 이름을 입력해 주세요.'; end if;
  select role into my_role from public.profiles where id = auth.uid() and is_active;
  if my_role is null then raise exception '활성 계정을 찾을 수 없습니다.'; end if;
  if my_role = 'guardian' and nullif(trim(p_phone), '') is null then raise exception '학부모 연락처를 입력해 주세요.'; end if;

  update public.profiles
  set display_name = trim(p_display_name), phone = nullif(trim(p_phone), '')
  where id = auth.uid();

  update public.teachers set name = trim(p_display_name) where profile_id = auth.uid();
  update public.students set name = trim(p_display_name), phone = nullif(trim(p_phone), '') where profile_id = auth.uid();
  update public.guardians set name = trim(p_display_name), phone = trim(p_phone) where profile_id = auth.uid();
end
$$;

revoke all on function public.save_my_account(text, text) from public;
grant execute on function public.save_my_account(text, text) to authenticated;
