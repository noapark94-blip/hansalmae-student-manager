create table if not exists public.account_help_requests (
  id uuid primary key default gen_random_uuid(),
  requester_name text not null,
  account_type text not null check (account_type in ('student','guardian','staff')),
  registered_phone text,
  reachable_phone text not null,
  reason text not null check (reason in ('phone_changed','sms_unavailable','other')),
  profile_id uuid references public.profiles(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','completed','rejected')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by uuid references public.profiles(id) on delete set null
);
create index if not exists account_help_requests_status_requested on public.account_help_requests(status,requested_at desc);
alter table public.account_help_requests enable row level security;
revoke all on table public.account_help_requests from public,anon,authenticated;
grant all on table public.account_help_requests to service_role;

create or replace function public.admin_account_help_board()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.current_user_role()='admin' then coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'requesterName',r.requester_name,'accountType',r.account_type,
    'registeredPhone',r.registered_phone,'reachablePhone',r.reachable_phone,
    'reason',r.reason,'profileId',r.profile_id,'requestedAt',r.requested_at,
    'matchedName',p.display_name,'matchedRole',p.role
  ) order by r.requested_at desc),'[]'::jsonb) else null end
  from public.account_help_requests r left join public.profiles p on p.id=r.profile_id
  where r.status='pending'
$$;
revoke all on function public.admin_account_help_board() from public;
grant execute on function public.admin_account_help_board() to authenticated;
notify pgrst,'reload schema';
