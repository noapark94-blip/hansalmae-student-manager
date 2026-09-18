create or replace function public.staff_edit_tuition_payment(
 p_payment_id uuid,p_expected jsonb,p_amount integer,p_method text,
 p_paid_on date,p_method_detail text,p_memo text
) returns uuid language plpgsql security definer set search_path=public as $$
declare
 payment public.tuition_payments%rowtype;
 charge public.tuition_charges%rowtype;
 charge_id_value uuid;
 other_paid bigint;
 new_allocations jsonb := '[]'::jsonb;
 item jsonb;
 allocated integer := 0;
 piece integer;
 position integer := 0;
 old_sum numeric;
begin
 if not coalesce(public.is_staff(),false) then raise exception '교직원만 납부 내역을 수정할 수 있습니다.'; end if;
 if p_amount is null or p_amount<=0 then raise exception '납부 금액은 1원 이상이어야 합니다.'; end if;
 if p_method is null or p_method not in ('transfer','card','cash','siru','other') then raise exception '결제 방법을 확인해 주세요.'; end if;
 if p_paid_on is null then raise exception '납부일을 입력해 주세요.'; end if;
 if p_method in ('siru','other') and coalesce(trim(p_method_detail),'')='' then raise exception '결제 방법의 상세 내용을 입력해 주세요.'; end if;
 select charge_id into charge_id_value from public.tuition_payments where id=p_payment_id;
 if not found then raise exception '납부 기록을 찾을 수 없습니다.'; end if;
 select * into charge from public.tuition_charges where id=charge_id_value for update;
 select * into payment from public.tuition_payments where id=p_payment_id and charge_id=charge_id_value for update;
 if not found then raise exception '납부 기록이 변경되었습니다. 다시 열어 주세요.'; end if;
 if p_expected is null or
   jsonb_build_object('amount',payment.amount,'method',payment.payment_method,'paidAt',payment.paid_at,'memo',payment.memo,'methodDetail',payment.method_detail,'allocations',payment.allocations)
   is distinct from p_expected then
   raise exception '다른 화면에서 납부 기록이 변경되었습니다. 다시 열어 주세요.';
 end if;
 select coalesce(sum(amount),0) into other_paid from public.tuition_payments where charge_id=charge_id_value and id<>p_payment_id;
 if p_amount>greatest(charge.base_amount-charge.discount_amount+charge.additional_amount,0)-other_paid then
   raise exception '다른 납부 내역을 합한 금액이 청구액을 초과합니다.';
 end if;
 if p_amount=payment.amount then new_allocations:=payment.allocations;
 elsif jsonb_array_length(payment.allocations)>0 then
   select sum((value->>'amount')::numeric) into old_sum from jsonb_array_elements(payment.allocations);
   if coalesce(old_sum,0)<=0 then raise exception '기존 과목별 납부 내역을 확인해 주세요.'; end if;
   for item in select value from jsonb_array_elements(payment.allocations) loop
     position:=position+1;
     piece:=case when position=jsonb_array_length(payment.allocations) then p_amount-allocated else floor((item->>'amount')::numeric*p_amount/old_sum)::integer end;
     allocated:=allocated+piece;
     new_allocations:=new_allocations||jsonb_build_array(jsonb_set(item,'{amount}',to_jsonb(piece)));
   end loop;
 end if;
 update public.tuition_payments set amount=p_amount,payment_method=p_method,
   paid_at=case when (payment.paid_at at time zone 'Asia/Seoul')::date=p_paid_on then payment.paid_at else (p_paid_on+time '12:00') at time zone 'Asia/Seoul' end,
   method_detail=case when p_method in ('siru','other') then nullif(trim(p_method_detail),'') else null end,
   memo=nullif(trim(p_memo),''),allocations=new_allocations
 where id=p_payment_id;
 perform public.refresh_tuition_charge_status(charge_id_value);
 return p_payment_id;
end $$;
revoke all on function public.staff_edit_tuition_payment(uuid,jsonb,integer,text,date,text,text) from public,anon;
grant execute on function public.staff_edit_tuition_payment(uuid,jsonb,integer,text,date,text,text) to authenticated;
