-- 기존 상담 테이블을 로그인 계정 상담자, 역할별 공유 조회, 홈 집계와 연결합니다.

alter table public.consultations
  add column consultant_profile_id uuid references public.profiles(id) on delete set null,
  add column consultation_type text not null default 'guardian'
    check (consultation_type in ('student', 'guardian', 'phone', 'academic', 'other'));

grant select, insert, update, delete on table public.consultations to authenticated;

create or replace function public.consultation_board()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'isStaff', public.is_staff(),
    'students', case when public.is_staff() then coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name)
      from public.students s where s.status in ('active', '재원')
    ), '[]'::jsonb) else '[]'::jsonb end,
    'overdueStudents', case when public.is_staff() then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', target.id,
        'name', target.name,
        'lastConsultedAt', target.last_consulted_at
      ) order by target.last_consulted_at nulls first, target.name)
      from (
        select s.id, s.name, max(c.consulted_at) as last_consulted_at
        from public.students s left join public.consultations c on c.student_id = s.id
        where s.status in ('active', '재원')
        group by s.id, s.name
        having max(c.consulted_at) is null or max(c.consulted_at) < now() - interval '30 days'
      ) target
    ), '[]'::jsonb) else '[]'::jsonb end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'studentId', s.id,
        'studentName', s.name,
        'consultantName', coalesce(p.display_name, t.name, '담당 선생님'),
        'consultedAt', c.consulted_at,
        'consultationType', c.consultation_type,
        'internalNote', case when public.is_staff() then c.internal_note else null end,
        'guardianSummary', case when public.is_staff() or public.current_user_role() = 'guardian' then c.guardian_summary else null end,
        'studentSummary', case when public.is_staff() or public.current_user_role() = 'student' then c.student_summary else null end,
        'nextContactOn', case when public.is_staff() then c.next_contact_on else null end
      ) order by c.consulted_at desc)
      from public.consultations c
      join public.students s on s.id = c.student_id
      left join public.profiles p on p.id = c.consultant_profile_id
      left join public.teachers t on t.id = c.teacher_id
      where public.is_staff()
        or (public.current_user_role() = 'student' and s.profile_id = auth.uid() and c.student_summary is not null)
        or (public.current_user_role() = 'guardian' and c.guardian_summary is not null and exists (
          select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
          where sg.student_id = s.id and g.profile_id = auth.uid()
        ))
    ), '[]'::jsonb)
  )
$$;

create or replace function public.staff_save_consultation(
  p_consultation_id uuid,
  p_student_id uuid,
  p_consultation_type text,
  p_consulted_at timestamptz,
  p_internal_note text,
  p_guardian_summary text,
  p_student_summary text,
  p_next_contact_on date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare saved_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 상담 기록을 저장할 수 있습니다.'; end if;
  if not exists (select 1 from public.students s where s.id = p_student_id) then raise exception '학생을 선택해 주세요.'; end if;
  if p_consultation_type not in ('student', 'guardian', 'phone', 'academic', 'other') then raise exception '상담 유형을 선택해 주세요.'; end if;
  if nullif(trim(p_internal_note), '') is null and nullif(trim(p_guardian_summary), '') is null and nullif(trim(p_student_summary), '') is null then
    raise exception '상담 내용을 하나 이상 입력해 주세요.';
  end if;

  if p_consultation_id is null then
    insert into public.consultations(student_id, consultant_profile_id, consulted_at, consultation_type, internal_note, guardian_summary, student_summary, next_contact_on)
    values (p_student_id, auth.uid(), p_consulted_at, p_consultation_type, nullif(trim(p_internal_note), ''), nullif(trim(p_guardian_summary), ''), nullif(trim(p_student_summary), ''), p_next_contact_on)
    returning id into saved_id;
  else
    update public.consultations set
      student_id = p_student_id,
      consultant_profile_id = auth.uid(),
      consulted_at = p_consulted_at,
      consultation_type = p_consultation_type,
      internal_note = nullif(trim(p_internal_note), ''),
      guardian_summary = nullif(trim(p_guardian_summary), ''),
      student_summary = nullif(trim(p_student_summary), ''),
      next_contact_on = p_next_contact_on
    where id = p_consultation_id returning id into saved_id;
    if saved_id is null then raise exception '상담 기록을 찾을 수 없습니다.'; end if;
  end if;
  return saved_id;
end
$$;

create or replace function public.staff_delete_consultation(p_consultation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 상담 기록을 삭제할 수 있습니다.'; end if;
  delete from public.consultations where id = p_consultation_id;
  if not found then raise exception '상담 기록을 찾을 수 없습니다.'; end if;
end
$$;

create or replace function public.consultation_dashboard_count()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_staff() then jsonb_build_object(
    'overdue', (select count(*) from (
      select s.id from public.students s left join public.consultations c on c.student_id = s.id
      where s.status in ('active', '재원') group by s.id
      having max(c.consulted_at) is null or max(c.consulted_at) < now() - interval '30 days'
    ) overdue),
    'upcoming', (select count(*) from public.consultations c where c.next_contact_on between current_date and current_date + 7)
  ) else jsonb_build_object('overdue', 0, 'upcoming', 0) end
$$;

revoke all on function public.consultation_board() from public;
revoke all on function public.staff_save_consultation(uuid, uuid, text, timestamptz, text, text, text, date) from public;
revoke all on function public.staff_delete_consultation(uuid) from public;
revoke all on function public.consultation_dashboard_count() from public;
grant execute on function public.consultation_board() to authenticated;
grant execute on function public.staff_save_consultation(uuid, uuid, text, timestamptz, text, text, text, date) to authenticated;
grant execute on function public.staff_delete_consultation(uuid) to authenticated;
grant execute on function public.consultation_dashboard_count() to authenticated;
