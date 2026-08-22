-- 모든 원비 그룹이 미설정이어도 누락 목록을 반환하도록 계산 결과를 보정합니다.

create or replace function public.calculate_student_tuition_policy(p_student_id uuid, p_month date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
with student_info as (
  select s.id, public.tuition_school_level(s.grade) school_level
  from public.students s where s.id=p_student_id
), active_enrollments as (
  select e.id enrollment_id, e.monthly_fee, e.use_default_fee, c.name class_name,
         c.subject_id, m.fee_group_id, g.name group_name, g.amount group_amount
  from public.enrollments e
  join public.classes c on c.id=e.class_id
  cross join student_info si
  left join public.tuition_subject_group_mappings m
    on m.subject_id=c.subject_id and m.school_level=si.school_level
  left join public.tuition_fee_groups g on g.id=m.fee_group_id and g.active
  where e.student_id=p_student_id
    and e.started_on < (date_trunc('month',p_month)::date + interval '1 month')::date
    and (e.ended_on is null or e.ended_on >= date_trunc('month',p_month)::date)
    and e.status in ('active','paused')
), grouped as (
  select fee_group_id,
         coalesce(group_name, class_name) label,
         (array_agg(enrollment_id order by enrollment_id))[1] enrollment_id,
         string_agg(distinct class_name, ' · ' order by class_name) classes,
         case
           when fee_group_id is null then coalesce(sum(monthly_fee),0)::integer
           when bool_or(not use_default_fee) then coalesce(max(monthly_fee) filter(where not use_default_fee),0)::integer
           else max(group_amount)
         end amount,
         fee_group_id is not null and max(group_amount) is null and not bool_or(not use_default_fee) missing
  from active_enrollments
  group by fee_group_id, coalesce(group_name,class_name)
), valid_groups as (
  select * from grouped where amount is not null
), group_ids as (
  select coalesce(array_agg(fee_group_id) filter(where fee_group_id is not null),array[]::uuid[]) ids from valid_groups
), combo as (
  select d.name,d.amount
  from public.tuition_combination_discounts d, student_info si, group_ids gi
  where d.active and d.school_level=si.school_level
    and d.required_group_ids <@ gi.ids
  order by d.amount desc,d.name
  limit 1
), recurring as (
  select
    coalesce(max(amount) filter(where kind='discount' and active),0)::integer personal_discount,
    coalesce(max(label) filter(where kind='discount' and active),'') personal_discount_label,
    coalesce(max(amount) filter(where kind='additional' and active),0)::integer additional,
    coalesce(max(label) filter(where kind='additional' and active),'') additional_label
  from public.tuition_recurring_adjustments where student_id=p_student_id
), totals as (
  select
    coalesce((select sum(amount) from valid_groups),0)::integer base_amount,
    coalesce((select amount from combo),0)::integer combo_discount,
    r.personal_discount,r.personal_discount_label,r.additional,r.additional_label
  from recurring r
)
select jsonb_build_object(
  'schoolLevel',(select school_level from student_info),
  'lineItems',coalesce((select jsonb_agg(jsonb_build_object(
    'enrollmentId',enrollment_id,'feeGroupId',fee_group_id,'className',label,'classes',classes,'amount',amount
  ) order by label) from valid_groups),'[]'::jsonb),
  'missingGroups',coalesce((select jsonb_agg(label order by label) from grouped where missing),'[]'::jsonb),
  'baseAmount',t.base_amount,
  'discountAmount',least(t.combo_discount+t.personal_discount,t.base_amount+t.additional),
  'combinationDiscount',t.combo_discount,
  'additionalAmount',t.additional,
  'memo',nullif(concat_ws(' · ',
    (select name from combo),
    nullif(t.personal_discount_label,''),
    nullif(t.additional_label,'')
  ),'')
)
from totals t
$$;
