-- 월별 수강료 청구, 할인·추가비용, 부분납부와 가족 조회 기능을 추가합니다.

create table public.tuition_charges (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  billing_month date not null check(billing_month=date_trunc('month',billing_month)::date),
  base_amount integer not null default 0 check(base_amount>=0),
  discount_amount integer not null default 0 check(discount_amount>=0),
  additional_amount integer not null default 0 check(additional_amount>=0),
  status text not null default 'open' check(status in ('open','partial','paid','waived')),
  memo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(student_id,billing_month),
  check(base_amount+additional_amount>=discount_amount)
);
create table public.tuition_payments (
  id uuid primary key default gen_random_uuid(),
  charge_id uuid not null references public.tuition_charges(id) on delete cascade,
  amount integer not null check(amount>0),
  payment_method text not null check(payment_method in ('cash','transfer','card','other')),
  paid_at timestamptz not null default now(),
  memo text,
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index tuition_charges_month_idx on public.tuition_charges(billing_month,status);
create index tuition_payments_charge_idx on public.tuition_payments(charge_id,paid_at desc);
alter table public.tuition_charges enable row level security;
alter table public.tuition_payments enable row level security;
create policy "staff_manage_tuition_charges" on public.tuition_charges for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy "family_read_tuition_charges" on public.tuition_charges for select to authenticated using(
  exists(select 1 from public.students s where s.id=student_id and s.profile_id=auth.uid()) or
  exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=student_id and g.profile_id=auth.uid())
);
create policy "staff_manage_tuition_payments" on public.tuition_payments for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy "family_read_tuition_payments" on public.tuition_payments for select to authenticated using(exists(
  select 1 from public.tuition_charges tc join public.students s on s.id=tc.student_id left join public.student_guardians sg on sg.student_id=s.id left join public.guardians g on g.id=sg.guardian_id
  where tc.id=charge_id and (s.profile_id=auth.uid() or g.profile_id=auth.uid())
));
grant select,insert,update,delete on public.tuition_charges,public.tuition_payments to authenticated;

create or replace function public.refresh_tuition_charge_status(p_charge_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare target_total integer; paid_total integer; current_status text;
begin
  select base_amount-discount_amount+additional_amount,status into target_total,current_status from public.tuition_charges where id=p_charge_id;
  if current_status='waived' then return; end if;
  select coalesce(sum(amount),0) into paid_total from public.tuition_payments where charge_id=p_charge_id;
  update public.tuition_charges set status=case when paid_total<=0 then 'open' when paid_total<target_total then 'partial' else 'paid' end,updated_at=now() where id=p_charge_id;
end $$;

create or replace function public.staff_generate_monthly_tuition(p_month date)
returns integer language plpgsql security definer set search_path=public as $$
declare month_start date:=date_trunc('month',p_month)::date; generated integer;
begin
  if not public.is_staff() then raise exception '교직원만 월 청구서를 생성할 수 있습니다.'; end if;
  insert into public.tuition_charges(student_id,billing_month,base_amount)
  select s.id,month_start,coalesce(sum(e.monthly_fee),0)::integer
  from public.students s join public.enrollments e on e.student_id=s.id
  where s.status in ('active','재원') and e.started_on<(month_start+interval '1 month')::date and (e.ended_on is null or e.ended_on>=month_start) and e.status in ('active','paused')
  group by s.id on conflict(student_id,billing_month) do nothing;
  get diagnostics generated=row_count; return generated;
end $$;

create or replace function public.staff_save_tuition_charge(p_charge_id uuid,p_base_amount integer,p_discount_amount integer,p_additional_amount integer,p_memo text,p_waived boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 청구 금액을 수정할 수 있습니다.'; end if;
  if least(p_base_amount,p_discount_amount,p_additional_amount)<0 or p_discount_amount>p_base_amount+p_additional_amount then raise exception '청구 금액을 확인해 주세요.'; end if;
  update public.tuition_charges set base_amount=p_base_amount,discount_amount=p_discount_amount,additional_amount=p_additional_amount,memo=nullif(trim(p_memo),''),status=case when p_waived then 'waived' else status end,updated_at=now() where id=p_charge_id;
  if not found then raise exception '청구서를 찾을 수 없습니다.'; end if;
  if not p_waived then update public.tuition_charges set status='open' where id=p_charge_id and status='waived'; perform public.refresh_tuition_charge_status(p_charge_id); end if;
end $$;

create or replace function public.staff_record_tuition_payment(p_charge_id uuid,p_amount integer,p_method text,p_paid_at timestamptz,p_memo text)
returns uuid language plpgsql security definer set search_path=public as $$
declare saved_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수납을 입력할 수 있습니다.'; end if;
  if p_amount<=0 then raise exception '납부 금액을 입력해 주세요.'; end if;
  if p_method not in ('cash','transfer','card','other') then raise exception '결제수단을 선택해 주세요.'; end if;
  if not exists(select 1 from public.tuition_charges where id=p_charge_id and status<>'waived') then raise exception '수납 가능한 청구서를 찾을 수 없습니다.'; end if;
  insert into public.tuition_payments(charge_id,amount,payment_method,paid_at,memo,recorded_by) values(p_charge_id,p_amount,p_method,p_paid_at,nullif(trim(p_memo),''),auth.uid()) returning id into saved_id;
  perform public.refresh_tuition_charge_status(p_charge_id); return saved_id;
end $$;

create or replace function public.tuition_board(p_month date)
returns jsonb language sql stable security definer set search_path=public as $$
  with visible as (
    select tc.*,s.name student_name,coalesce((select string_agg(c.name,' · ' order by c.name) from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=s.id and e.started_on<(tc.billing_month+interval '1 month')::date and (e.ended_on is null or e.ended_on>=tc.billing_month)),'수강 클래스 없음') classes
    from public.tuition_charges tc join public.students s on s.id=tc.student_id
    where tc.billing_month=date_trunc('month',p_month)::date and (public.is_staff() or s.profile_id=auth.uid() or exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=s.id and g.profile_id=auth.uid()))
  ) select jsonb_build_object('isStaff',public.is_staff(),'items',coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'studentId',v.student_id,'studentName',v.student_name,'classes',v.classes,'baseAmount',v.base_amount,'discountAmount',v.discount_amount,'additionalAmount',v.additional_amount,'totalAmount',v.base_amount-v.discount_amount+v.additional_amount,'paidAmount',coalesce(p.paid,0),'balance',greatest(v.base_amount-v.discount_amount+v.additional_amount-coalesce(p.paid,0),0),'status',v.status,'memo',v.memo,
    'payments',coalesce(p.items,'[]'::jsonb)
  ) order by v.student_name),'[]'::jsonb)) from visible v left join lateral(select sum(tp.amount)::integer paid,jsonb_agg(jsonb_build_object('id',tp.id,'amount',tp.amount,'method',tp.payment_method,'paidAt',tp.paid_at,'memo',tp.memo) order by tp.paid_at desc) items from public.tuition_payments tp where tp.charge_id=v.id)p on true
$$;

revoke all on function public.staff_generate_monthly_tuition(date),public.staff_save_tuition_charge(uuid,integer,integer,integer,text,boolean),public.staff_record_tuition_payment(uuid,integer,text,timestamptz,text),public.tuition_board(date) from public;
grant execute on function public.staff_generate_monthly_tuition(date),public.staff_save_tuition_charge(uuid,integer,integer,integer,text,boolean),public.staff_record_tuition_payment(uuid,integer,text,timestamptz,text),public.tuition_board(date) to authenticated;
