-- Keep cancelled receipts in an immutable archive; active payment aggregates stay unchanged.
create table public.tuition_payment_cancellations(
 payment_id uuid primary key,
 charge_id uuid not null references public.tuition_charges(id) on delete restrict,
 payment_snapshot jsonb not null,
 reason text not null check(length(trim(reason)) between 1 and 500),
 cancelled_at timestamptz not null default now(),
 cancelled_by uuid references public.profiles(id) on delete set null
);
create index tuition_payment_cancellations_charge_idx on public.tuition_payment_cancellations(charge_id,cancelled_at desc);
alter table public.tuition_payment_cancellations enable row level security;
revoke all on public.tuition_payment_cancellations from public,anon,authenticated;
grant select on public.tuition_payment_cancellations to authenticated;
create policy staff_read_payment_cancellations on public.tuition_payment_cancellations for select to authenticated
 using(coalesce(public.is_staff(),false));

create or replace function public.staff_cancel_tuition_payment(p_payment_id uuid,p_expected jsonb,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare
 payment public.tuition_payments%rowtype;
 cid uuid;
begin
 if not coalesce(public.is_staff(),false) then raise exception '교직원만 납부를 취소할 수 있습니다.'; end if;
 if coalesce(length(trim(p_reason)),0) not between 1 and 500 then raise exception '취소 사유를 1~500자로 입력해 주세요.'; end if;
 select charge_id into cid from public.tuition_payments where id=p_payment_id;
 if not found then raise exception '이미 취소되었거나 변경된 납부 기록입니다. 다시 확인해 주세요.'; end if;
 -- Match the charge-first lock order used by payment edits and registrations.
 perform 1 from public.tuition_charges where id=cid for update;
 select * into payment from public.tuition_payments where id=p_payment_id and charge_id=cid for update;
 if not found then raise exception '이미 취소되었거나 변경된 납부 기록입니다. 다시 확인해 주세요.'; end if;
 if p_expected is null or jsonb_build_object(
   'amount',payment.amount,'method',payment.payment_method,'paidAt',payment.paid_at,
   'memo',payment.memo,'methodDetail',payment.method_detail,'allocations',payment.allocations
 ) is distinct from p_expected then
   raise exception '납부 내역이 변경되었습니다. 다시 확인한 후 취소해 주세요.';
 end if;
 insert into public.tuition_payment_cancellations(payment_id,charge_id,payment_snapshot,reason,cancelled_by)
 values(payment.id,cid,to_jsonb(payment),trim(p_reason),auth.uid());
 -- The complete original row is archived above in this same transaction.
 delete from public.tuition_payments where id=payment.id;
 perform public.refresh_tuition_charge_status(cid);
 return payment.id;
end $$;
revoke all on function public.staff_cancel_tuition_payment(uuid,jsonb,text) from public,anon;
grant execute on function public.staff_cancel_tuition_payment(uuid,jsonb,text) to authenticated;
