create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.student_grade_progression_cycles (
  academic_year integer primary key,
  prepared_at timestamptz not null default now(),
  prepared_by uuid references public.profiles(id) on delete set null,
  early_applied_at timestamptz,
  completed_at timestamptz
);

create table if not exists public.student_grade_progression_items (
  id uuid primary key default gen_random_uuid(),
  academic_year integer not null references public.student_grade_progression_cycles(academic_year) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  previous_grade text,
  previous_school text,
  proposed_grade text,
  proposed_school text,
  transition_kind text not null check (transition_kind in ('automatic','school_change','graduation','repeat_year')),
  decision text,
  approval_status text not null default 'pending' check (approval_status in ('automatic','pending','approved')),
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  unique (academic_year, student_id)
);

alter table public.student_grade_progression_cycles enable row level security;
alter table public.student_grade_progression_items enable row level security;
revoke all on public.student_grade_progression_cycles, public.student_grade_progression_items from anon, authenticated;

create or replace function public.prepare_grade_progression(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_year integer := extract(year from v_today)::integer + 1;
  v_count integer;
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 다음 학년도를 준비할 수 있습니다.'; end if;
  if not p_force and extract(month from v_today) < 11 then raise exception '다음 학년도 준비는 11월 1일부터 사용할 수 있습니다.'; end if;
  insert into public.student_grade_progression_cycles(academic_year, prepared_by) values(v_year, auth.uid()) on conflict do nothing;
  insert into public.student_grade_progression_items(academic_year, student_id, previous_grade, previous_school, proposed_grade, transition_kind, approval_status)
  select v_year, s.id, s.grade, s.school,
    case s.grade when '초1' then '초2' when '초2' then '초3' when '초3' then '초4' when '초4' then '초5' when '초5' then '초6'
      when '중1' then '중2' when '중2' then '중3' when '고1' then '고2' when '고2' then '고3' end,
    case when s.grade in ('초6','중3') then 'school_change' when s.grade='고3' then 'graduation' when s.grade='재수' then 'repeat_year' else 'automatic' end,
    case when s.grade in ('초6','중3','고3','재수') then 'pending' else 'automatic' end
  from public.students s
  where s.status='active' and s.grade in ('초1','초2','초3','초4','초5','초6','중1','중2','중3','고1','고2','고3','재수')
  on conflict (academic_year, student_id) do nothing;
  get diagnostics v_count = row_count;
  return jsonb_build_object('academicYear',v_year,'created',v_count);
end $$;

create or replace function public.admin_grade_progression_board()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_today date := (now() at time zone 'Asia/Seoul')::date; v_year integer := extract(year from v_today)::integer + 1;
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 학년 전환을 확인할 수 있습니다.'; end if;
  return jsonb_build_object(
    'academicYear',v_year,
    'available',extract(month from v_today)>=11,
    'prepared',exists(select 1 from public.student_grade_progression_cycles where academic_year=v_year),
    'earlyApplied',exists(select 1 from public.student_grade_progression_cycles where academic_year=v_year and early_applied_at is not null),
    'pendingCount',(select count(*) from public.student_grade_progression_items where academic_year=v_year and approval_status='pending'),
    'readyCount',(select count(*) from public.student_grade_progression_items where academic_year=v_year and approval_status in ('automatic','approved') and applied_at is null),
    'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'studentId',i.student_id,'studentName',s.name,'previousGrade',i.previous_grade,'previousSchool',i.previous_school,'proposedGrade',i.proposed_grade,'proposedSchool',i.proposed_school,'transitionKind',i.transition_kind,'decision',i.decision,'approvalStatus',i.approval_status,'appliedAt',i.applied_at) order by s.name) from public.student_grade_progression_items i join public.students s on s.id=i.student_id where i.academic_year=v_year),'[]'::jsonb),
    'schools',coalesce((select jsonb_agg(name order by name) from public.academy_schools where active),'[]'::jsonb)
  );
end $$;

create or replace function public.admin_approve_grade_progression(p_item_id uuid, p_decision text, p_school text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_item public.student_grade_progression_items%rowtype;
begin
  if public.current_user_role() <> 'admin' then raise exception '관리자만 승인할 수 있습니다.'; end if;
  select * into v_item from public.student_grade_progression_items where id=p_item_id for update;
  if not found or v_item.applied_at is not null then raise exception '처리할 수 없는 항목입니다.'; end if;
  if v_item.transition_kind='school_change' then
    if nullif(trim(p_school),'') is null then raise exception '진학 학교를 선택해 주세요.'; end if;
    update public.student_grade_progression_items set proposed_grade=case previous_grade when '초6' then '중1' else '고1' end, proposed_school=trim(p_school), decision='진학', approval_status='approved', approved_by=auth.uid(), approved_at=now() where id=p_item_id;
  elsif v_item.transition_kind='graduation' then
    if p_decision not in ('graduated','repeat','withdrawn','stay') then raise exception '진로를 선택해 주세요.'; end if;
    update public.student_grade_progression_items set proposed_grade=case p_decision when 'repeat' then '재수' when 'stay' then '고3' else previous_grade end, decision=p_decision, approval_status='approved', approved_by=auth.uid(), approved_at=now() where id=p_item_id;
  elsif v_item.transition_kind='repeat_year' then
    if p_decision not in ('repeat','withdrawn') then raise exception '재수 유지 또는 퇴원을 선택해 주세요.'; end if;
    update public.student_grade_progression_items set proposed_grade='재수', decision=p_decision, approval_status='approved', approved_by=auth.uid(), approved_at=now() where id=p_item_id;
  else raise exception '승인이 필요하지 않은 항목입니다.';
  end if;
end $$;

create or replace function public.apply_ready_grade_progression(p_year integer, p_early boolean default false, p_require_complete boolean default false)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  if p_early and public.current_user_role() <> 'admin' then raise exception '관리자만 조기 전환할 수 있습니다.'; end if;
  if p_early and extract(month from (now() at time zone 'Asia/Seoul')::date) < 11 then raise exception '조기 전환은 11월 1일부터 사용할 수 있습니다.'; end if;
  if p_require_complete and exists(select 1 from public.student_grade_progression_items where academic_year=p_year and approval_status='pending') then raise exception '승인 대기 학생을 모두 처리한 뒤 전환해 주세요.'; end if;
  with ready as (
    select * from public.student_grade_progression_items where academic_year=p_year and applied_at is null and approval_status in ('automatic','approved')
  ), changed as (
    update public.students s set
      grade=coalesce(r.proposed_grade,s.grade), school=coalesce(r.proposed_school,s.school),
      status=case when r.decision in ('graduated','withdrawn') then 'completed' else s.status end
    from ready r where s.id=r.student_id returning r.id
  )
  update public.student_grade_progression_items i set applied_at=now() from changed c where i.id=c.id;
  get diagnostics v_count = row_count;
  update public.student_grade_progression_cycles set early_applied_at=case when p_early then coalesce(early_applied_at,now()) else early_applied_at end,
    completed_at=case when not exists(select 1 from public.student_grade_progression_items where academic_year=p_year and applied_at is null) then now() else completed_at end where academic_year=p_year;
  return v_count;
end $$;

create or replace function public.admin_apply_grade_progression_now()
returns integer language plpgsql security definer set search_path=public as $$
declare v_year integer := extract(year from (now() at time zone 'Asia/Seoul')::date)::integer + 1;
begin return public.apply_ready_grade_progression(v_year,true,true); end $$;

create or replace function public.run_new_year_grade_progression()
returns void language plpgsql security definer set search_path=public as $$
declare v_today date := (now() at time zone 'Asia/Seoul')::date; v_year integer := extract(year from v_today)::integer;
begin
  if extract(month from v_today)=1 and extract(day from v_today)=1 then
    insert into public.student_grade_progression_cycles(academic_year) values(v_year) on conflict do nothing;
    insert into public.student_grade_progression_items(academic_year, student_id, previous_grade, previous_school, proposed_grade, transition_kind, approval_status)
    select v_year, s.id, s.grade, s.school,
      case s.grade when '초1' then '초2' when '초2' then '초3' when '초3' then '초4' when '초4' then '초5' when '초5' then '초6'
        when '중1' then '중2' when '중2' then '중3' when '고1' then '고2' when '고2' then '고3' end,
      case when s.grade in ('초6','중3') then 'school_change' when s.grade='고3' then 'graduation' when s.grade='재수' then 'repeat_year' else 'automatic' end,
      case when s.grade in ('초6','중3','고3','재수') then 'pending' else 'automatic' end
    from public.students s where s.status='active' and s.grade in ('초1','초2','초3','초4','초5','초6','중1','중2','중3','고1','고2','고3','재수')
    on conflict (academic_year, student_id) do nothing;
    perform public.apply_ready_grade_progression(v_year,false,false);
  end if;
end $$;

revoke all on function public.prepare_grade_progression(boolean), public.admin_grade_progression_board(), public.admin_approve_grade_progression(uuid,text,text), public.apply_ready_grade_progression(integer,boolean,boolean), public.admin_apply_grade_progression_now(), public.run_new_year_grade_progression() from public, anon;
grant execute on function public.prepare_grade_progression(boolean), public.admin_grade_progression_board(), public.admin_approve_grade_progression(uuid,text,text), public.admin_apply_grade_progression_now() to authenticated;

select cron.schedule('hansalmae-new-year-grade-progression','5 15 * * *',$$select public.run_new_year_grade_progression()$$)
where not exists(select 1 from cron.job where jobname='hansalmae-new-year-grade-progression');
