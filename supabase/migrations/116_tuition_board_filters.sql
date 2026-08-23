-- 원비 정산 목록에서 기존 학생·수강 정보를 기준으로 교차 필터를 제공합니다.

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
      s.school,
      s.grade,
      coalesce((
        select string_agg(c.name, ' · ' order by c.name)
        from public.enrollments e
        join public.classes c on c.id = e.class_id
        where e.student_id = s.id
          and e.started_on < (tc.billing_month + interval '1 month')::date
          and (e.ended_on is null or e.ended_on >= tc.billing_month)
      ), '수강 클래스 없음') as classes,
      coalesce((
        select array_agg(distinct c.name order by c.name)
        from public.enrollments e
        join public.classes c on c.id = e.class_id
        where e.student_id = s.id
          and e.started_on < (tc.billing_month + interval '1 month')::date
          and (e.ended_on is null or e.ended_on >= tc.billing_month)
      ), array[]::text[]) as class_names,
      coalesce((
        select array_agg(distinct coalesce(sub.main_subject, c.subject) order by coalesce(sub.main_subject, c.subject))
        from public.enrollments e
        join public.classes c on c.id = e.class_id
        left join public.academy_subjects sub on sub.id = c.subject_id
        where e.student_id = s.id
          and e.started_on < (tc.billing_month + interval '1 month')::date
          and (e.ended_on is null or e.ended_on >= tc.billing_month)
      ), array[]::text[]) as subjects
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
      'school', v.school,
      'grade', v.grade,
      'subjects', v.subjects,
      'classNames', v.class_names,
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

revoke all on function public.tuition_board(date) from public;
grant execute on function public.tuition_board(date) to authenticated;
