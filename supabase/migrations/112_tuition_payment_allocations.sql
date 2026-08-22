-- 납부 기록에 과목별 배분과 결제수단 상세를 보존합니다.

alter table public.tuition_payments
  add column if not exists allocations jsonb not null default '[]'::jsonb,
  add column if not exists method_detail text;

create or replace function public.staff_record_tuition_payment_breakdown(
  p_charge_id uuid,
  p_allocations jsonb,
  p_method text,
  p_paid_on date,
  p_method_detail text,
  p_memo text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  saved_id uuid;
  item jsonb;
  charge_items jsonb;
  item_amount numeric;
  payment_total integer := 0;
  charge_balance integer;
  allowed_keys text[];
begin
  if not public.is_staff() then
    raise exception '교직원만 납부를 등록할 수 있습니다.';
  end if;
  if p_method not in ('transfer', 'card', 'cash', 'siru', 'other') then
    raise exception '결제 방법을 확인해 주세요.';
  end if;
  if p_method in ('siru', 'other') and coalesce(trim(p_method_detail), '') = '' then
    raise exception '결제 방법의 상세 내용을 입력해 주세요.';
  end if;
  if p_paid_on is null then
    raise exception '납부일을 확인해 주세요.';
  end if;
  if jsonb_typeof(p_allocations) <> 'array' or jsonb_array_length(p_allocations) = 0 then
    raise exception '과목별 납부 금액을 입력해 주세요.';
  end if;

  select
    tc.line_items,
    greatest(
      tc.base_amount - tc.discount_amount + tc.additional_amount
      - coalesce((select sum(tp.amount) from public.tuition_payments tp where tp.charge_id = tc.id), 0),
      0
    )::integer,
    array(
      select coalesce(nullif(value ->> 'enrollmentId', ''), 'line-' || (ordinality - 1)::text)
      from jsonb_array_elements(tc.line_items) with ordinality
    ) || case when tc.additional_amount > 0 then array['additional'] else array[]::text[] end
  into charge_items, charge_balance, allowed_keys
  from public.tuition_charges tc
  where tc.id = p_charge_id
  for update;

  if not found then
    raise exception '청구서를 찾을 수 없습니다.';
  end if;
  if charge_balance <= 0 then
    raise exception '남은 미수금이 없습니다.';
  end if;

  for item in select value from jsonb_array_elements(p_allocations)
  loop
    if jsonb_typeof(item) <> 'object'
      or coalesce(trim(item ->> 'key'), '') = ''
      or coalesce(trim(item ->> 'label'), '') = ''
      or jsonb_typeof(item -> 'amount') <> 'number'
      or not ((item ->> 'key') = any(allowed_keys)) then
      raise exception '과목별 납부 내역을 확인해 주세요.';
    end if;
    item_amount := (item ->> 'amount')::numeric;
    if item_amount < 0 or item_amount <> trunc(item_amount) or item_amount > 2147483647 then
      raise exception '과목별 납부 금액을 확인해 주세요.';
    end if;
    payment_total := payment_total + item_amount::integer;
  end loop;

  if payment_total <= 0 or payment_total > charge_balance then
    raise exception '납부 금액이 미수금을 초과하거나 0원입니다.';
  end if;

  insert into public.tuition_payments(
    charge_id, amount, payment_method, paid_at, memo, recorded_by,
    allocations, method_detail
  )
  values(
    p_charge_id, payment_total, p_method,
    (p_paid_on::timestamp + time '12:00') at time zone 'Asia/Seoul',
    nullif(trim(p_memo), ''), auth.uid(),
    p_allocations, nullif(trim(p_method_detail), '')
  )
  returning id into saved_id;

  perform public.refresh_tuition_charge_status(p_charge_id);
  return saved_id;
end
$$;

create or replace function public.tuition_board(p_month date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with visible as (
    select
      tc.*,
      s.name as student_name,
      coalesce((
        select string_agg(c.name, ' · ' order by c.name)
        from public.enrollments e
        join public.classes c on c.id = e.class_id
        where e.student_id = s.id
          and e.started_on < (tc.billing_month + interval '1 month')::date
          and (e.ended_on is null or e.ended_on >= tc.billing_month)
      ), '수강 클래스 없음') as classes
    from public.tuition_charges tc
    join public.students s on s.id = tc.student_id
    where tc.billing_month = date_trunc('month', p_month)::date
      and (
        public.is_staff()
        or s.profile_id = auth.uid()
        or exists(
          select 1
          from public.student_guardians sg
          join public.guardians g on g.id = sg.guardian_id
          where sg.student_id = s.id and g.profile_id = auth.uid()
        )
      )
  )
  select jsonb_build_object(
    'isStaff', public.is_staff(),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', v.id,
      'studentId', v.student_id,
      'studentName', v.student_name,
      'classes', v.classes,
      'lineItems', v.line_items,
      'baseAmount', v.base_amount,
      'discountAmount', v.discount_amount,
      'additionalAmount', v.additional_amount,
      'totalAmount', v.base_amount - v.discount_amount + v.additional_amount,
      'paidAmount', coalesce(p.paid, 0),
      'balance', greatest(v.base_amount - v.discount_amount + v.additional_amount - coalesce(p.paid, 0), 0),
      'status', v.status,
      'memo', v.memo,
      'payments', coalesce(p.items, '[]'::jsonb)
    ) order by v.student_name), '[]'::jsonb)
  )
  from visible v
  left join lateral (
    select
      sum(tp.amount)::integer as paid,
      jsonb_agg(jsonb_build_object(
        'id', tp.id,
        'amount', tp.amount,
        'method', tp.payment_method,
        'methodDetail', tp.method_detail,
        'paidAt', tp.paid_at,
        'memo', tp.memo,
        'allocations', tp.allocations
      ) order by tp.paid_at desc) as items
    from public.tuition_payments tp
    where tp.charge_id = v.id
  ) p on true
$$;

revoke all on function public.staff_record_tuition_payment_breakdown(uuid, jsonb, text, date, text, text) from public;
grant execute on function public.staff_record_tuition_payment_breakdown(uuid, jsonb, text, date, text, text) to authenticated;
