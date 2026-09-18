
create table public.academy_account_balance (
 id boolean primary key default true check(id),
 amount bigint not null check(amount between 0 and 999999999999),
 checked_on date not null,
 version integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id) on delete set null
);
alter table public.academy_account_balance enable row level security;
revoke all on public.academy_account_balance from public,anon,authenticated;
grant select on public.academy_account_balance to authenticated;
create policy admin_read_account_balance on public.academy_account_balance for select to authenticated using(public.current_user_role()='admin');

create function public.admin_account_balance() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 계좌 잔액을 확인할 수 있습니다.'; end if;
 return (select to_jsonb(b) from public.academy_account_balance b where id=true);
end $$;

create function public.admin_save_account_balance(p_amount bigint,p_checked_on date,p_expected_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_row public.academy_account_balance%rowtype; saved public.academy_account_balance%rowtype;
begin
 if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 계좌 잔액을 수정할 수 있습니다.'; end if;
 if p_amount is null or p_amount<0 or p_amount>999999999999 or p_checked_on is null or p_checked_on<'1900-01-01'::date or p_checked_on>(now() at time zone 'Asia/Seoul')::date then raise exception '잔액과 확인 기준일을 확인해 주세요. 미래 날짜는 입력할 수 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('academy-account-balance',0));
 select * into current_row from public.academy_account_balance where id=true for update;
 if current_row.version is distinct from p_expected_version then raise exception '다른 곳에서 잔액이 변경되었습니다. 최신 잔액을 다시 불러온 후 수정해 주세요.'; end if;
 insert into public.academy_account_balance(id,amount,checked_on,updated_by) values(true,p_amount,p_checked_on,auth.uid())
 on conflict(id) do update set amount=excluded.amount,checked_on=excluded.checked_on,version=academy_account_balance.version+1,updated_at=now(),updated_by=auth.uid()
 returning * into saved;
 return to_jsonb(saved);
end $$;
revoke all on function public.admin_account_balance(),public.admin_save_account_balance(bigint,date,integer) from public,anon;
grant execute on function public.admin_account_balance(),public.admin_save_account_balance(bigint,date,integer) to authenticated;
