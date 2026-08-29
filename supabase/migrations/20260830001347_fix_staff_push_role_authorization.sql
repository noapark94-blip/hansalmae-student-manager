create or replace function public.set_current_device_push_subscription(
  p_endpoint text,
  p_p256dh text default null,
  p_auth text default null,
  p_user_agent text default null,
  p_enabled boolean default true
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if nullif(trim(coalesce(p_endpoint,'')),'') is null then raise exception '기기 구독 주소가 필요합니다.'; end if;

  delete from public.push_subscriptions where endpoint=p_endpoint;

  if not p_enabled then return false; end if;
  if not exists (
    select 1
    from public.profiles p
    where p.id=auth.uid()
      and p.is_active is true
      and (p.role::text='guardian' or public.is_staff())
  ) then
    raise exception '이 계정은 기기 알림을 사용할 수 없습니다.';
  end if;
  if nullif(trim(coalesce(p_p256dh,'')),'') is null or nullif(trim(coalesce(p_auth,'')),'') is null then
    raise exception '기기 구독 키가 필요합니다.';
  end if;

  insert into public.push_subscriptions(profile_id,endpoint,p256dh,auth,user_agent,updated_at)
  values(auth.uid(),p_endpoint,p_p256dh,p_auth,p_user_agent,now())
  on conflict(profile_id,endpoint) do update
  set p256dh=excluded.p256dh,auth=excluded.auth,user_agent=excluded.user_agent,updated_at=now();
  return true;
end;
$$;

revoke all on function public.set_current_device_push_subscription(text,text,text,text,boolean) from public,anon;
grant execute on function public.set_current_device_push_subscription(text,text,text,text,boolean) to authenticated;
notify pgrst,'reload schema';
