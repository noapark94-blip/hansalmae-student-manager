-- 학교급·과목 원비 그룹과 과목 결합 할인을 자동 계산합니다.

create table public.tuition_fee_groups (
  id uuid primary key default gen_random_uuid(),
  school_level text not null check (school_level in ('middle','high')),
  name text not null,
  amount integer check (amount is null or amount >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_level, name)
);

create table public.tuition_subject_group_mappings (
  subject_id uuid not null references public.academy_subjects(id) on delete cascade,
  school_level text not null check (school_level in ('middle','high')),
  fee_group_id uuid not null references public.tuition_fee_groups(id) on delete cascade,
  primary key (subject_id, school_level)
);
create index tuition_subject_group_fee_group_idx on public.tuition_subject_group_mappings(fee_group_id);

create table public.tuition_combination_discounts (
  id uuid primary key default gen_random_uuid(),
  school_level text not null check (school_level in ('middle','high')),
  name text not null,
  amount integer not null check (amount >= 0),
  required_group_ids uuid[] not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(required_group_ids) >= 2)
);
create index tuition_combination_discounts_level_idx on public.tuition_combination_discounts(school_level) where active;

alter table public.enrollments
  add column if not exists use_default_fee boolean not null default true;

alter table public.tuition_fee_groups enable row level security;
alter table public.tuition_subject_group_mappings enable row level security;
alter table public.tuition_combination_discounts enable row level security;

create policy "staff_manage_tuition_fee_groups" on public.tuition_fee_groups
for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "staff_manage_tuition_subject_group_mappings" on public.tuition_subject_group_mappings
for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "staff_manage_tuition_combination_discounts" on public.tuition_combination_discounts
for all to authenticated using (public.is_staff()) with check (public.is_staff());

grant select, insert, update, delete on public.tuition_fee_groups to authenticated;
grant select, insert, update, delete on public.tuition_subject_group_mappings to authenticated;
grant select, insert, update, delete on public.tuition_combination_discounts to authenticated;

insert into public.tuition_fee_groups(school_level, name)
values
  ('middle','중등 영어'),('middle','중등 수학'),('middle','중등 국어'),
  ('high','고등 영어'),('high','고등 수학'),('high','고등 국어'),
  ('high','고등 선택수학')
on conflict (school_level, name) do nothing;

insert into public.tuition_subject_group_mappings(subject_id, school_level, fee_group_id)
select s.id, levels.school_level, g.id
from public.academy_subjects s
cross join (values ('middle'::text),('high'::text)) levels(school_level)
join public.tuition_fee_groups g
  on g.school_level = levels.school_level
 and g.name = case
   when levels.school_level='middle' then '중등 '||s.main_subject
   else '고등 '||s.main_subject
 end
where s.parent_id is null and s.main_subject in ('영어','수학','국어')
on conflict (subject_id, school_level) do nothing;

insert into public.tuition_subject_group_mappings(subject_id, school_level, fee_group_id)
select s.id, 'high', g.id
from public.academy_subjects s
join public.tuition_fee_groups g on g.school_level='high' and g.name='고등 선택수학'
where s.parent_id is not null and s.main_subject='수학'
on conflict (subject_id, school_level) do nothing;

create or replace function public.tuition_school_level(p_grade text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when trim(coalesce(p_grade,'')) like '중%' then 'middle'
    when trim(coalesce(p_grade,'')) like '고%' then 'high'
    else null
  end
$$;

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
  select coalesce(sum(amount),0)::integer base_amount,
         coalesce((select amount from combo),0)::integer combo_discount,
         r.personal_discount,r.personal_discount_label,r.additional,r.additional_label
  from valid_groups cross join recurring r
  group by r.personal_discount,r.personal_discount_label,r.additional,r.additional_label
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

create or replace function public.tuition_fee_policy_settings()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
select case when public.is_staff() then jsonb_build_object(
  'groups',coalesce((select jsonb_agg(jsonb_build_object(
    'id',g.id,'schoolLevel',g.school_level,'name',g.name,'amount',g.amount,'active',g.active
  ) order by g.school_level,g.name) from public.tuition_fee_groups g),'[]'::jsonb),
  'subjects',coalesce((select jsonb_agg(jsonb_build_object(
    'id',s.id,'name',s.name,'mainSubject',s.main_subject,'parentId',s.parent_id,
    'middleGroupId',(select m.fee_group_id from public.tuition_subject_group_mappings m where m.subject_id=s.id and m.school_level='middle'),
    'highGroupId',(select m.fee_group_id from public.tuition_subject_group_mappings m where m.subject_id=s.id and m.school_level='high')
  ) order by s.main_subject,s.name) from public.academy_subjects s where s.active),'[]'::jsonb),
  'discounts',coalesce((select jsonb_agg(jsonb_build_object(
    'id',d.id,'schoolLevel',d.school_level,'name',d.name,'amount',d.amount,
    'groupIds',d.required_group_ids,'active',d.active
  ) order by d.school_level,d.name) from public.tuition_combination_discounts d),'[]'::jsonb)
) else jsonb_build_object('groups','[]'::jsonb,'subjects','[]'::jsonb,'discounts','[]'::jsonb) end
$$;

create or replace function public.staff_save_tuition_fee_policy(
  p_groups jsonb,
  p_mappings jsonb,
  p_discounts jsonb,
  p_month date,
  p_apply_current boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  calculated jsonb;
  charge_row record;
  updated_count integer := 0;
  skipped_paid_count integer := 0;
begin
  if not public.is_staff() then raise exception '교직원만 원비 정책을 저장할 수 있습니다.'; end if;
  if jsonb_typeof(p_groups)<>'array' or jsonb_typeof(p_mappings)<>'array' or jsonb_typeof(p_discounts)<>'array' then
    raise exception '원비 정책 형식을 확인해 주세요.';
  end if;

  for item in select value from jsonb_array_elements(p_groups) loop
    if (item->>'amount') is not null and ((item->>'amount')::numeric<0 or (item->>'amount')::numeric<>trunc((item->>'amount')::numeric)) then
      raise exception '기본 원비를 확인해 주세요.';
    end if;
    update public.tuition_fee_groups
    set amount=case when (item->>'amount') is null then null else (item->>'amount')::integer end,
        active=coalesce((item->>'active')::boolean,true),updated_at=now()
    where id=(item->>'id')::uuid;
    if not found then raise exception '원비 그룹을 찾을 수 없습니다.'; end if;
  end loop;

  for item in select value from jsonb_array_elements(p_mappings) loop
    if coalesce(item->>'groupId','')='' then
      delete from public.tuition_subject_group_mappings
      where subject_id=(item->>'subjectId')::uuid and school_level=item->>'schoolLevel';
    else
      insert into public.tuition_subject_group_mappings(subject_id,school_level,fee_group_id)
      values((item->>'subjectId')::uuid,item->>'schoolLevel',(item->>'groupId')::uuid)
      on conflict(subject_id,school_level) do update set fee_group_id=excluded.fee_group_id;
    end if;
  end loop;

  delete from public.tuition_combination_discounts;
  for item in select value from jsonb_array_elements(p_discounts) loop
    if (item->>'amount')::numeric<0 or jsonb_array_length(item->'groupIds')<2 then
      raise exception '결합 할인 조건을 확인해 주세요.';
    end if;
    insert into public.tuition_combination_discounts(
      id,school_level,name,amount,required_group_ids,active
    ) values(
      coalesce((item->>'id')::uuid,gen_random_uuid()),item->>'schoolLevel',
      trim(item->>'name'),(item->>'amount')::integer,
      array(select jsonb_array_elements_text(item->'groupIds')::uuid),
      coalesce((item->>'active')::boolean,true)
    );
  end loop;

  if p_apply_current then
    for charge_row in
      select tc.*,
        exists(select 1 from public.tuition_payments tp where tp.charge_id=tc.id) has_payment
      from public.tuition_charges tc
      where tc.billing_month=date_trunc('month',p_month)::date
      for update
    loop
      if charge_row.has_payment then skipped_paid_count:=skipped_paid_count+1; continue; end if;
      calculated:=public.calculate_student_tuition_policy(charge_row.student_id,p_month);
      if jsonb_array_length(calculated->'missingGroups')>0 then continue; end if;
      update public.tuition_charges set
        line_items=calculated->'lineItems',
        base_amount=(calculated->>'baseAmount')::integer,
        discount_amount=(calculated->>'discountAmount')::integer,
        additional_amount=(calculated->>'additionalAmount')::integer,
        memo=calculated->>'memo',
        updated_at=now()
      where id=charge_row.id;
      perform public.refresh_tuition_charge_status(charge_row.id);
      updated_count:=updated_count+1;
    end loop;
  end if;

  return jsonb_build_object('updated',updated_count,'skippedPaid',skipped_paid_count);
end
$$;

create or replace function public.staff_generate_monthly_tuition(p_month date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  month_start date:=date_trunc('month',p_month)::date;
  student_row record;
  calculated jsonb;
  generated integer:=0;
begin
  if not public.is_staff() then raise exception '교직원만 월 청구서를 생성할 수 있습니다.'; end if;
  for student_row in
    select distinct s.id from public.students s
    join public.enrollments e on e.student_id=s.id
    where s.status in ('active','재원')
      and e.started_on<(month_start+interval '1 month')::date
      and (e.ended_on is null or e.ended_on>=month_start)
      and e.status in ('active','paused')
  loop
    if exists(select 1 from public.tuition_charges where student_id=student_row.id and billing_month=month_start) then continue; end if;
    calculated:=public.calculate_student_tuition_policy(student_row.id,month_start);
    if (calculated->>'schoolLevel') is null or jsonb_array_length(calculated->'missingGroups')>0 then continue; end if;
    insert into public.tuition_charges(
      student_id,billing_month,line_items,base_amount,discount_amount,additional_amount,memo
    ) values(
      student_row.id,month_start,calculated->'lineItems',
      (calculated->>'baseAmount')::integer,(calculated->>'discountAmount')::integer,
      (calculated->>'additionalAmount')::integer,calculated->>'memo'
    );
    generated:=generated+1;
  end loop;
  return generated;
end
$$;

create or replace function public.tuition_billing_settings()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object(
  'id',s.id,'name',s.name,
  'enrollments',coalesce((select jsonb_agg(jsonb_build_object(
    'id',e.id,'className',c.name,
    'monthlyFee',case when e.use_default_fee then coalesce(g.amount,e.monthly_fee,0) else coalesce(e.monthly_fee,0) end,
    'useDefault',e.use_default_fee,
    'feeGroupName',g.name
  ) order by c.name)
  from public.enrollments e
  join public.classes c on c.id=e.class_id
  left join public.tuition_subject_group_mappings m
    on m.subject_id=c.subject_id and m.school_level=public.tuition_school_level(s.grade)
  left join public.tuition_fee_groups g on g.id=m.fee_group_id and g.active
  where e.student_id=s.id and e.status='active'),'[]'::jsonb),
  'discount',coalesce((select jsonb_build_object('label',a.label,'amount',a.amount,'active',a.active) from public.tuition_recurring_adjustments a where a.student_id=s.id and a.kind='discount'),jsonb_build_object('label','고정 할인','amount',0,'active',true)),
  'additional',coalesce((select jsonb_build_object('label',a.label,'amount',a.amount,'active',a.active) from public.tuition_recurring_adjustments a where a.student_id=s.id and a.kind='additional'),jsonb_build_object('label','차량·교재비','amount',0,'active',true))
) order by s.name),'[]'::jsonb) else '[]'::jsonb end
from public.students s where s.status in ('active','재원')
$$;

create or replace function public.staff_save_enrollment_fee(p_enrollment_id uuid,p_monthly_fee integer)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 수강료를 설정할 수 있습니다.'; end if;
  if p_monthly_fee<0 then raise exception '월 수강료를 확인해 주세요.'; end if;
  update public.enrollments set monthly_fee=p_monthly_fee,use_default_fee=false where id=p_enrollment_id;
  if not found then raise exception '수강 정보를 찾을 수 없습니다.'; end if;
end
$$;

create or replace function public.staff_use_default_enrollment_fee(p_enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 수강료를 설정할 수 있습니다.'; end if;
  update public.enrollments set use_default_fee=true where id=p_enrollment_id;
  if not found then raise exception '수강 정보를 찾을 수 없습니다.'; end if;
end
$$;

revoke all on function public.calculate_student_tuition_policy(uuid,date) from public;
revoke all on function public.tuition_fee_policy_settings() from public;
revoke all on function public.staff_save_tuition_fee_policy(jsonb,jsonb,jsonb,date,boolean) from public;
revoke all on function public.staff_use_default_enrollment_fee(uuid) from public;
grant execute on function public.calculate_student_tuition_policy(uuid,date) to authenticated;
grant execute on function public.tuition_fee_policy_settings() to authenticated;
grant execute on function public.staff_save_tuition_fee_policy(jsonb,jsonb,jsonb,date,boolean) to authenticated;
grant execute on function public.staff_use_default_enrollment_fee(uuid) to authenticated;
