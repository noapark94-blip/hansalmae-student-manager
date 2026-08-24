alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

create table if not exists public.password_reset_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  requested_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','completed','cancelled')),
  processed_at timestamptz,
  processed_by uuid references public.profiles(id) on delete set null
);

create unique index if not exists password_reset_requests_one_pending
  on public.password_reset_requests(profile_id) where status='pending';
alter table public.password_reset_requests enable row level security;
revoke all on table public.password_reset_requests from anon,authenticated;

create or replace function public.find_login_id(p_name text,p_phone text)
returns text language plpgsql security definer set search_path=public,auth as $$
declare found_email text; matched integer;
begin
  if length(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'))<10 or nullif(trim(p_name),'') is null then return null; end if;
  select count(*),min(u.email) into matched,found_email
  from public.profiles p join auth.users u on u.id=p.id
  where p.is_active and lower(trim(p.display_name))=lower(trim(p_name))
    and regexp_replace(coalesce(nullif(p.phone,''),(select s.phone from public.students s where s.profile_id=p.id limit 1),(select g.phone from public.guardians g where g.profile_id=p.id limit 1),''),'[^0-9]','','g')=regexp_replace(p_phone,'[^0-9]','','g');
  return case when matched=1 then found_email else null end;
end $$;

create or replace function public.request_password_reset(p_name text,p_phone text)
returns void language plpgsql security definer set search_path=public as $$
declare target_id uuid; matched integer;
begin
  if length(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'))<10 or nullif(trim(p_name),'') is null then return; end if;
  select count(*),min(p.id) into matched,target_id from public.profiles p
  where p.is_active and lower(trim(p.display_name))=lower(trim(p_name))
    and regexp_replace(coalesce(nullif(p.phone,''),(select s.phone from public.students s where s.profile_id=p.id limit 1),(select g.phone from public.guardians g where g.profile_id=p.id limit 1),''),'[^0-9]','','g')=regexp_replace(p_phone,'[^0-9]','','g');
  if matched=1 then
    insert into public.password_reset_requests(profile_id) values(target_id)
    on conflict(profile_id) where status='pending' do update set requested_at=now();
  end if;
end $$;

create or replace function public.admin_password_reset_board()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.current_user_role()='admin' then coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'profileId',p.id,'displayName',p.display_name,'role',p.role,
    'phone',left(regexp_replace(coalesce(nullif(p.phone,''),(select s.phone from public.students s where s.profile_id=p.id limit 1),(select g.phone from public.guardians g where g.profile_id=p.id limit 1),''),'[^0-9]','','g'),3)||'-****-'||right(regexp_replace(coalesce(nullif(p.phone,''),(select s.phone from public.students s where s.profile_id=p.id limit 1),(select g.phone from public.guardians g where g.profile_id=p.id limit 1),''),'[^0-9]','','g'),4),
    'requestedAt',r.requested_at,'status',r.status
  ) order by r.requested_at desc),'[]'::jsonb) else null end
  from public.password_reset_requests r join public.profiles p on p.id=r.profile_id
  where r.status='pending'
$$;

create or replace function public.internal_complete_password_reset(p_request_id uuid,p_processed_by uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.password_reset_requests set status='completed',processed_at=now(),processed_by=p_processed_by where id=p_request_id and status='pending';
  if not found then raise exception '처리할 비밀번호 요청을 찾을 수 없습니다.'; end if;
end $$;

create or replace function public.complete_temporary_password_change()
returns void language sql security definer set search_path=public as $$
  update public.profiles set must_change_password=false where id=auth.uid()
$$;

revoke all on function public.find_login_id(text,text) from public;
revoke all on function public.request_password_reset(text,text) from public;
revoke all on function public.admin_password_reset_board() from public;
revoke all on function public.internal_complete_password_reset(uuid,uuid) from public;
revoke all on function public.complete_temporary_password_change() from public;
grant execute on function public.find_login_id(text,text) to anon,authenticated;
grant execute on function public.request_password_reset(text,text) to anon,authenticated;
grant execute on function public.admin_password_reset_board() to authenticated;
grant execute on function public.internal_complete_password_reset(uuid,uuid) to service_role;
grant execute on function public.complete_temporary_password_change() to authenticated;

notify pgrst,'reload schema';
