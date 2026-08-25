create table if not exists public.account_recovery_challenges (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade,
  purpose text not null check (purpose in ('id','password')),
  phone_hash text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts between 0 and 5),
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists account_recovery_challenges_phone_created
  on public.account_recovery_challenges(phone_hash,created_at desc);
create index if not exists account_recovery_challenges_expiry
  on public.account_recovery_challenges(expires_at);

alter table public.account_recovery_challenges enable row level security;
revoke all on table public.account_recovery_challenges from public,anon,authenticated;
grant all on table public.account_recovery_challenges to service_role;

-- 기존 이름·연락처만으로 아이디를 노출하거나 관리자 요청을 만드는 공개 경로를 닫습니다.
revoke execute on function public.find_login_id(text,text) from anon,authenticated;
revoke execute on function public.request_password_reset(text,text) from anon,authenticated;

notify pgrst,'reload schema';
