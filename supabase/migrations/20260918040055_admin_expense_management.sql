-- Admin-only expense ledger. Deletion retains history; receipts are private.
create table public.academy_expenses (
  id uuid primary key,
  spent_on date not null,
  category text not null check (category in ('임대료','급여','관리비','교재비','광고비','비품','기타')),
  vendor text not null check (length(trim(vendor)) between 1 and 120),
  amount integer not null check (amount > 0),
  payment_method text not null check (payment_method in ('transfer','card','cash','other')),
  memo text not null default '' check (length(memo)<=2000),
  receipt_path text,
  receipt_name text,
  version integer not null default 1,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index academy_expenses_month_idx on public.academy_expenses(spent_on desc) where deleted_at is null;
alter table public.academy_expenses enable row level security;
revoke all on public.academy_expenses from anon,authenticated;
grant select on public.academy_expenses to authenticated;
create policy admin_read_expenses on public.academy_expenses for select to authenticated
using (public.current_user_role()='admin');

create function public.admin_expense_board(p_month date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare month_start date:=date_trunc('month',p_month)::date; result jsonb;
begin
  if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 지출 내역을 확인할 수 있습니다.'; end if;
  if p_month is null then raise exception '조회할 월을 선택해 주세요.'; end if;
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(e) order by e.spent_on desc,e.created_at desc) from public.academy_expenses e where e.deleted_at is null and e.spent_on>=month_start and e.spent_on<(month_start+interval '1 month')::date),'[]'::jsonb),
    'receipts',coalesce((select sum(p.amount) from public.tuition_payments p where p.paid_at >= (month_start::timestamp at time zone 'Asia/Seoul') and p.paid_at < ((month_start+interval '1 month') at time zone 'Asia/Seoul')),0)
  ) into result;
  return result;
end $$;

create function public.admin_save_expense(p_id uuid,p_expected_version integer,p_values jsonb) returns public.academy_expenses
language plpgsql security definer set search_path='' as $$
declare existing public.academy_expenses%rowtype; saved public.academy_expenses%rowtype; receipt text:=nullif(p_values->>'receipt_path','');
begin
  if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 지출을 등록·수정할 수 있습니다.'; end if;
  if p_id is null or p_values is null then raise exception '지출 정보를 확인해 주세요.'; end if;
  -- Serialize same-id retries; the client retains its id after a network failure.
  perform pg_advisory_xact_lock(hashtextextended('expense:'||p_id::text,0));
  select * into existing from public.academy_expenses where id=p_id for update;
  if found then
    if existing.deleted_at is not null or p_expected_version is distinct from existing.version then
      raise exception '다른 곳에서 변경된 내역입니다. 목록을 새로고침해 주세요.';
    end if;
  elsif p_expected_version is not null then
    raise exception '수정할 지출을 찾을 수 없습니다.';
  end if;
  if receipt is not null then
    if split_part(receipt,'/',1)<>p_id::text or not exists(select 1 from storage.objects where bucket_id='expense-receipts' and name=receipt) then
      raise exception '영수증 첨부를 확인해 주세요.';
    end if;
  end if;
  insert into public.academy_expenses(id,spent_on,category,vendor,amount,payment_method,memo,receipt_path,receipt_name,created_by,updated_by)
  values(p_id,(p_values->>'spent_on')::date,p_values->>'category',trim(p_values->>'vendor'),(p_values->>'amount')::integer,p_values->>'payment_method',coalesce(p_values->>'memo',''),receipt,case when receipt is not null then left(p_values->>'receipt_name',255) end,auth.uid(),auth.uid())
  on conflict(id) do update set spent_on=excluded.spent_on,category=excluded.category,vendor=excluded.vendor,amount=excluded.amount,payment_method=excluded.payment_method,memo=excluded.memo,receipt_path=excluded.receipt_path,receipt_name=excluded.receipt_name,version=academy_expenses.version+1,updated_at=now(),updated_by=auth.uid()
  returning * into saved;
  return saved;
end $$;

create function public.admin_delete_expense(p_id uuid,p_expected_version integer) returns void
language plpgsql security definer set search_path='' as $$
begin
  if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 지출을 삭제할 수 있습니다.'; end if;
  update public.academy_expenses set deleted_at=now(),updated_at=now(),updated_by=auth.uid(),version=version+1
    where id=p_id and version=p_expected_version and deleted_at is null;
  if not found then raise exception '다른 곳에서 변경된 내역입니다. 목록을 새로고침해 주세요.'; end if;
end $$;
revoke all on function public.admin_expense_board(date),public.admin_save_expense(uuid,integer,jsonb),public.admin_delete_expense(uuid,integer) from public,anon;
grant execute on function public.admin_expense_board(date),public.admin_save_expense(uuid,integer,jsonb),public.admin_delete_expense(uuid,integer) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('expense-receipts','expense-receipts',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']);
create policy admin_expense_receipt_read on storage.objects for select to authenticated
using(bucket_id='expense-receipts' and public.current_user_role()='admin');
create policy admin_expense_receipt_insert on storage.objects for insert to authenticated
with check(bucket_id='expense-receipts' and public.current_user_role()='admin');
create policy admin_expense_receipt_delete on storage.objects for delete to authenticated
using(bucket_id='expense-receipts' and public.current_user_role()='admin' and not exists(select 1 from public.academy_expenses e where e.receipt_path=name));
