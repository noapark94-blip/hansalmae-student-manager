-- Sub administrators inherit teacher capabilities and additionally manage
-- outbound notices and SMS. Keep messaging authority limited to admin roles.
create or replace function public.can_manage_communications()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select coalesce((
    select role in ('admin','sub_admin') and is_active
    from public.profiles
    where id=auth.uid()
  ),false)
$$;

notify pgrst,'reload schema';
