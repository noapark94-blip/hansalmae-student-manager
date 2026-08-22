-- 월 청구서에 과목별 금액 스냅샷을 보존하고 이번 달 금액을 과목별로 수정합니다.

alter table public.tuition_charges
  add column if not exists line_items jsonb not null default '[]'::jsonb;

update public.tuition_charges tc
set line_items = coalesce((
  select case
    when coalesce(sum(e.monthly_fee), 0)::integer = tc.base_amount then
      coalesce(jsonb_agg(jsonb_build_object(
        'enrollmentId', e.id,
        'className', c.name,
        'amount', coalesce(e.monthly_fee, 0)
      ) order by c.name), '[]'::jsonb)
    else jsonb_build_array(jsonb_build_object(
      'enrollmentId', null,
      'className', '기존 기본 수강료',
      'amount', tc.base_amount
    ))
  end
  from public.enrollments e
  join public.classes c on c.id = e.class_id
  where e.student_id = tc.student_id
    and e.started_on < (tc.billing_month + interval '1 month')::date
    and (e.ended_on is null or e.ended_on >= tc.billing_month)
), jsonb_build_array(jsonb_build_object(
  'enrollmentId', null,
  'className', '기존 기본 수강료',
  'amount', tc.base_amount
)))
where tc.line_items = '[]'::jsonb;

create or replace function public.staff_generate_monthly_tuition(p_month date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  month_start date := date_trunc('month', p_month)::date;
  generated integer;
begin
  if not public.is_staff() then
    raise exception '교직원만 월 청구서를 생성할 수 있습니다.';
  end if;

  with base as (
    select
      s.id,
      coalesce(sum(e.monthly_fee), 0)::integer as base_amount,
      jsonb_agg(jsonb_build_object(
        'enrollmentId', e.id,
        'className', c.name,
        'amount', coalesce(e.monthly_fee, 0)
      ) order by c.name) as line_items
    from public.students s
    join public.enrollments e on e.student_id = s.id
    join public.classes c on c.id = e.class_id
    where s.status in ('active', '재원')
      and e.started_on < (month_start + interval '1 month')::date
      and (e.ended_on is null or e.ended_on >= month_start)
      and e.status in ('active', 'paused')
    group by s.id
  ), rules as (
    select
      b.*,
      coalesce(d.amount, 0) as discount_amount,
      coalesce(a.amount, 0) as additional_amount,
      nullif(concat_ws(' · ', d.label, a.label), '') as memo
    from base b
    left join public.tuition_recurring_adjustments d
      on d.student_id = b.id and d.kind = 'discount' and d.active
    left join public.tuition_recurring_adjustments a
      on a.student_id = b.id and a.kind = 'additional' and a.active
  )
  insert into public.tuition_charges(
    student_id, billing_month, base_amount, discount_amount,
    additional_amount, memo, line_items
  )
  select
    id, month_start, base_amount,
    least(discount_amount, base_amount + additional_amount),
    additional_amount, memo, line_items
  from rules
  on conflict(student_id, billing_month) do nothing;

  get diagnostics generated = row_count;
  return generated;
end
$$;

create or replace function public.staff_save_tuition_charge_breakdown(
  p_charge_id uuid,
  p_line_items jsonb,
  p_discount_amount integer,
  p_additional_amount integer,
  p_memo text,
  p_waived boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  calculated_base integer := 0;
  item_amount numeric;
begin
  if not public.is_staff() then
    raise exception '교직원만 청구 금액을 수정할 수 있습니다.';
  end if;
  if jsonb_typeof(p_line_items) <> 'array' or jsonb_array_length(p_line_items) = 0 then
    raise exception '과목별 청구 금액을 확인해 주세요.';
  end if;
  if least(p_discount_amount, p_additional_amount) < 0 then
    raise exception '할인·추가 비용을 확인해 주세요.';
  end if;

  for item in select value from jsonb_array_elements(p_line_items)
  loop
    if jsonb_typeof(item) <> 'object'
      or coalesce(trim(item ->> 'className'), '') = ''
      or jsonb_typeof(item -> 'amount') <> 'number' then
      raise exception '과목별 청구 금액을 확인해 주세요.';
    end if;
    item_amount := (item ->> 'amount')::numeric;
    if item_amount < 0 or item_amount <> trunc(item_amount) or item_amount > 2147483647 then
      raise exception '과목별 청구 금액을 확인해 주세요.';
    end if;
    calculated_base := calculated_base + item_amount::integer;
  end loop;

  if p_discount_amount > calculated_base + p_additional_amount then
    raise exception '할인 금액이 청구 금액보다 큽니다.';
  end if;

  update public.tuition_charges
  set line_items = p_line_items,
      base_amount = calculated_base,
      discount_amount = p_discount_amount,
      additional_amount = p_additional_amount,
      memo = nullif(trim(p_memo), ''),
      status = case when p_waived then 'waived' else status end,
      updated_at = now()
  where id = p_charge_id;

  if not found then
    raise exception '청구서를 찾을 수 없습니다.';
  end if;
  if not p_waived then
    update public.tuition_charges
    set status = 'open'
    where id = p_charge_id and status = 'waived';
    perform public.refresh_tuition_charge_status(p_charge_id);
  end if;
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
        'paidAt', tp.paid_at,
        'memo', tp.memo
      ) order by tp.paid_at desc) as items
    from public.tuition_payments tp
    where tp.charge_id = v.id
  ) p on true
$$;

revoke all on function public.staff_save_tuition_charge_breakdown(uuid, jsonb, integer, integer, text, boolean) from public;
grant execute on function public.staff_save_tuition_charge_breakdown(uuid, jsonb, integer, integer, text, boolean) to authenticated;
