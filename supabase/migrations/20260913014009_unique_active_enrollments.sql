-- Preserve redundant rows for maintenance, retaining the original enrollment period.
lock table public.enrollments in share row exclusive mode;
create table if not exists public.enrollment_dedup_audit (
  duplicate_id uuid primary key,
  retained_id uuid not null,
  original_row jsonb not null,
  archived_at timestamptz not null default now()
);
alter table public.enrollment_dedup_audit enable row level security;
revoke all on public.enrollment_dedup_audit from public, anon, authenticated;
grant all on public.enrollment_dedup_audit to service_role;
do $$ begin
  if exists (
    select 1 from public.enrollments where status='active'
    group by student_id,class_id
    having count(*)>1 and count(distinct jsonb_build_array(monthly_fee,use_default_fee,ended_on))>1
  ) then raise exception '중복 수강료 또는 종료일이 달라 수동 확인이 필요합니다.'; end if;
end $$;
with ranked as (
  select e.*, row_number() over w rn,first_value(id) over w retained_id
  from public.enrollments e where status='active'
  window w as (partition by student_id,class_id order by started_on,id)
)
insert into public.enrollment_dedup_audit(duplicate_id,retained_id,original_row)
select r.id,r.retained_id,to_jsonb(e) from ranked r join public.enrollments e on e.id=r.id
where r.rn>1 on conflict(duplicate_id) do nothing;
delete from public.enrollments e using public.enrollment_dedup_audit a
where e.id=a.duplicate_id and e.status='active'
  and exists(select 1 from public.enrollments k where k.id=a.retained_id and k.status='active');
create unique index if not exists enrollments_one_active_student_class
  on public.enrollments(student_id,class_id) where status='active';
