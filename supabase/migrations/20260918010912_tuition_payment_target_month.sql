-- Preview is read-only. A new monthly charge is created only with a successful payment.
create or replace function public.staff_tuition_payment_target(p_student_id uuid,p_month date)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 m date:=date_trunc('month',p_month)::date;
 c public.tuition_charges%rowtype;
 policy jsonb; student_name text; paid integer:=0; payments jsonb:='[]'; total integer;
begin
 if not coalesce(public.is_staff(),false) then raise exception '교직원만 납부 정보를 조회할 수 있습니다.'; end if;
 if m is null then raise exception '원비 귀속월을 선택해 주세요.'; end if;
 select name into student_name from public.students where id=p_student_id;
 if not found then raise exception '학생을 찾을 수 없습니다.'; end if;
 select * into c from public.tuition_charges where student_id=p_student_id and billing_month=m;
 if not found then
   if not exists(select 1 from public.enrollments where student_id=p_student_id and status in ('active','paused')
     and started_on<(m+interval '1 month')::date and (ended_on is null or ended_on>=m)) then
     raise exception '선택한 달에 등록된 수강 내역이 없습니다.';
   end if;
   policy:=public.calculate_student_tuition_policy(p_student_id,m);
   if policy->>'schoolLevel' is null or coalesce(jsonb_array_length(policy->'missingGroups'),1)>0 then
     raise exception '선택한 달의 기본 원비 설정을 먼저 확인해 주세요.';
   end if;
   c.line_items:=policy->'lineItems';c.base_amount:=(policy->>'baseAmount')::integer;
   c.discount_amount:=(policy->>'discountAmount')::integer;c.additional_amount:=(policy->>'additionalAmount')::integer;
   c.memo:=policy->>'memo';c.status:='open';
 else
   select coalesce(sum(amount),0)::integer,coalesce(jsonb_agg(jsonb_build_object(
     'id',id,'amount',amount,'method',payment_method,'methodDetail',method_detail,'paidAt',paid_at,'memo',memo,'allocations',allocations
   ) order by paid_at desc,id),'[]') into paid,payments from public.tuition_payments where charge_id=c.id;
 end if;
 total:=greatest(c.base_amount-c.discount_amount+c.additional_amount,0);
 return jsonb_build_object('id',coalesce(c.id::text,''),'studentId',p_student_id,'studentName',student_name,
   'school',null,'grade',null,'subjects','[]'::jsonb,'classNames','[]'::jsonb,'classes','',
   'lineItems',c.line_items,'baseAmount',c.base_amount,'discountAmount',c.discount_amount,'additionalAmount',c.additional_amount,
   'totalAmount',total,'paidAmount',paid,'balance',greatest(total-paid,0),'status',c.status,'memo',c.memo,'payments',payments);
end $$;

create or replace function public.staff_record_tuition_payment_for_month(
 p_student_id uuid,p_month date,p_expected jsonb,p_allocations jsonb,p_method text,p_paid_on date,p_method_detail text,p_memo text
) returns uuid language plpgsql security definer set search_path=public as $$
declare
 m date:=date_trunc('month',p_month)::date; target jsonb; cid uuid;
begin
 if not coalesce(public.is_staff(),false) then raise exception '교직원만 납부를 등록할 수 있습니다.'; end if;
 if m is null or p_paid_on is null then raise exception '귀속월과 납부일을 확인해 주세요.'; end if;
 if p_method is null or p_method not in ('transfer','card','cash','siru','other') then raise exception '결제 방법을 확인해 주세요.'; end if;
 if p_allocations is null or jsonb_typeof(p_allocations)<>'array' then raise exception '과목별 납부 금액을 확인해 주세요.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_student_id::text||':'||m::text,0));
 select id into cid from public.tuition_charges where student_id=p_student_id and billing_month=m for update;
 target:=public.staff_tuition_payment_target(p_student_id,m);
 if p_expected is null or target is distinct from p_expected then
   raise exception '청구 또는 납부 내역이 변경되었습니다. 귀속월을 다시 선택하여 확인해 주세요.';
 end if;
 if target->>'status'='waived' then raise exception '면제된 청구서에는 납부를 등록할 수 없습니다.'; end if;
 if cid is null then
   insert into public.tuition_charges(student_id,billing_month,line_items,base_amount,discount_amount,additional_amount,memo)
   values(p_student_id,m,target->'lineItems',(target->>'baseAmount')::integer,(target->>'discountAmount')::integer,
     (target->>'additionalAmount')::integer,target->>'memo')
   on conflict(student_id,billing_month) do nothing returning id into cid;
   if cid is null then raise exception '청구서가 생성되었습니다. 귀속월을 다시 선택하여 확인해 주세요.'; end if;
 end if;
 return public.staff_record_tuition_payment_breakdown(cid,p_allocations,p_method,p_paid_on,p_method_detail,p_memo);
end $$;
revoke all on function public.staff_tuition_payment_target(uuid,date) from public,anon;
revoke all on function public.staff_record_tuition_payment_for_month(uuid,date,jsonb,jsonb,text,date,text,text) from public,anon;
grant execute on function public.staff_tuition_payment_target(uuid,date) to authenticated;
grant execute on function public.staff_record_tuition_payment_for_month(uuid,date,jsonb,jsonb,text,date,text,text) to authenticated;
