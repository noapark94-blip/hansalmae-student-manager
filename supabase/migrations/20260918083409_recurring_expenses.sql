
create table public.academy_expense_recurrences (
 id uuid primary key,
 source_expense_id uuid not null unique references public.academy_expenses(id),
 start_month date not null check(start_month=date_trunc('month',start_month)::date),
 repeat_day integer not null check(repeat_day between 1 and 31),
 active boolean not null default true,
 version integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references public.profiles(id) on delete set null
);
alter table public.academy_expense_recurrences enable row level security;
revoke all on public.academy_expense_recurrences from public,anon,authenticated;
grant select on public.academy_expense_recurrences to authenticated;
create policy admin_read_expense_recurrences on public.academy_expense_recurrences for select to authenticated using(public.current_user_role()='admin');
alter table public.academy_expenses add column recurrence_id uuid references public.academy_expense_recurrences(id), add column scheduled_month date;
alter table public.academy_expenses add constraint expense_recurrence_month check((recurrence_id is null and scheduled_month is null) or (recurrence_id is not null and scheduled_month is not null and scheduled_month=date_trunc('month',scheduled_month)::date));
create unique index expense_recurrence_month_unique on public.academy_expenses(recurrence_id,scheduled_month) where recurrence_id is not null;

alter function public.admin_save_expense(uuid,integer,jsonb) rename to admin_save_expense_base;
revoke all on function public.admin_save_expense_base(uuid,integer,jsonb) from public,anon,authenticated;

create function public.admin_save_expense(p_id uuid,p_expected_version integer,p_values jsonb) returns public.academy_expenses
language plpgsql security definer set search_path='' as $$
declare old public.academy_expenses%rowtype; saved public.academy_expenses%rowtype;
 rec public.academy_expense_recurrences%rowtype;
 rid uuid:=nullif(p_values->>'recurrence_id','')::uuid;
 target date:=nullif(p_values->>'scheduled_month','')::date;
 fixed boolean:=coalesce((p_values->>'is_fixed')::boolean,false);
begin
 if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 지출을 등록·수정할 수 있습니다.'; end if;
 select * into old from public.academy_expenses where id=p_id;
 if old.id is not null then
   if rid is not null and rid is distinct from old.recurrence_id then raise exception '고정지출 연결을 변경할 수 없습니다.'; end if;
   rid:=old.recurrence_id; target:=old.scheduled_month;
 end if;
 if rid is not null then
   select * into rec from public.academy_expense_recurrences where id=rid for update;
   if not found or rec.version is distinct from (p_values->>'recurrence_version')::integer then raise exception '고정지출 설정이 변경되었습니다. 새로고침해 주세요.'; end if;
   if old.id is null then
     if not rec.active or target is null or target<rec.start_month or target<>date_trunc('month',target)::date then raise exception '지급 예정 정보를 확인해 주세요.'; end if;
     if exists(select 1 from public.academy_expenses where recurrence_id=rid and scheduled_month=target) then raise exception '이 달의 고정지출은 이미 처리되었습니다.'; end if;
   end if;
 end if;
 saved:=public.admin_save_expense_base(p_id,p_expected_version,p_values);
 if rid is null and fixed then
   rid:=p_id; target:=date_trunc('month',saved.spent_on)::date;
   insert into public.academy_expense_recurrences(id,source_expense_id,start_month,repeat_day,updated_by)
   values(rid,p_id,(target+interval '1 month')::date,extract(day from saved.spent_on)::integer,auth.uid());
 elsif rid is not null and p_values ? 'is_fixed' and (fixed is distinct from rec.active or rec.source_expense_id=p_id) then
   update public.academy_expense_recurrences set active=fixed,repeat_day=case when source_expense_id=p_id then extract(day from saved.spent_on)::integer else repeat_day end,version=version+1,updated_at=now(),updated_by=auth.uid() where id=rid;
 end if;
 if rid is not null then
   update public.academy_expenses set recurrence_id=rid,scheduled_month=target where id=p_id returning * into saved;
 end if;
 return saved;
end $$;

create function public.admin_set_expense_recurrence(p_id uuid,p_expected_version integer,p_active boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 고정지출을 설정할 수 있습니다.'; end if;
 update public.academy_expense_recurrences set active=p_active,version=version+1,updated_at=now(),updated_by=auth.uid()
 where id=p_id and version=p_expected_version;
 if not found then raise exception '고정지출 설정이 변경되었습니다. 새로고침해 주세요.'; end if;
end $$;

create or replace function public.admin_expense_board(p_month date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare month_start date:=date_trunc('month',p_month)::date; result jsonb;
begin
 if public.current_user_role() is distinct from 'admin' then raise exception '관리자만 지출 내역을 확인할 수 있습니다.'; end if;
 if p_month is null then raise exception '조회할 월을 선택해 주세요.'; end if;
 select jsonb_build_object(
 'items',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('is_fixed',coalesce(r.active,false),'recurrence_version',r.version) order by e.spent_on desc,e.created_at desc)
 from public.academy_expenses e left join public.academy_expense_recurrences r on r.id=e.recurrence_id
 where e.deleted_at is null and e.spent_on>=month_start and e.spent_on<(month_start+interval '1 month')::date),'[]'::jsonb),
 'scheduled',coalesce((select jsonb_agg(jsonb_build_object(
 'recurrence_id',r.id,'recurrence_version',r.version,'scheduled_month',month_start,
 'spent_on',month_start+(least(r.repeat_day,extract(day from month_start+interval '1 month - 1 day')::integer)-1),
 'category',e.category,'vendor',regexp_replace(e.vendor,'^[0-9]{1,2}월[[:space:]]*',''),'amount',e.amount,
 'payment_method',e.payment_method,'memo','','is_fixed',true) order by r.repeat_day,e.vendor)
 from public.academy_expense_recurrences r join public.academy_expenses e on e.id=r.source_expense_id
 where r.active and r.start_month<=month_start and not exists(select 1 from public.academy_expenses done where done.recurrence_id=r.id and done.scheduled_month=month_start)),'[]'::jsonb),
 'receipts',coalesce((select sum(p.amount) from public.tuition_payments p where p.paid_at >= (month_start::timestamp at time zone 'Asia/Seoul') and p.paid_at < ((month_start+interval '1 month') at time zone 'Asia/Seoul')),0)
 ) into result;
 return result;
end $$;
revoke all on function public.admin_save_expense(uuid,integer,jsonb),public.admin_set_expense_recurrence(uuid,integer,boolean) from public,anon;
grant execute on function public.admin_save_expense(uuid,integer,jsonb),public.admin_set_expense_recurrence(uuid,integer,boolean) to authenticated;
