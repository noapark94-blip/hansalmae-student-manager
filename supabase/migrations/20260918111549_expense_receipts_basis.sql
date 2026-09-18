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
 'receipts_billing',coalesce((select sum(p.amount) from public.tuition_payments p join public.tuition_charges c on c.id=p.charge_id where c.billing_month>=month_start and c.billing_month<(month_start+interval '1 month')::date),0),
 'receipts',coalesce((select sum(p.amount) from public.tuition_payments p where p.paid_at >= (month_start::timestamp at time zone 'Asia/Seoul') and p.paid_at < ((month_start+interval '1 month') at time zone 'Asia/Seoul')),0)
 ) into result;
 return result;
end $$;
