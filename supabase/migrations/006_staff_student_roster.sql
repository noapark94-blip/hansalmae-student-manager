-- 보호자 연결 테이블의 권한을 열지 않고 관리자·교사에게 필요한 학생 목록만 반환합니다.
create or replace function public.staff_student_roster()
returns table (
  id uuid,
  name text,
  school text,
  grade text,
  status text,
  enrollments jsonb
)
language sql
stable
security definer set search_path = public
as $$
  select
    s.id,
    s.name,
    s.school,
    s.grade,
    s.status,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'class_id', e.class_id,
          'status', e.status,
          'classes', jsonb_build_object('name', c.name, 'subject', c.subject)
        )
      ) filter (where e.id is not null),
      '[]'::jsonb
    ) as enrollments
  from public.students s
  left join public.enrollments e on e.student_id = s.id
  left join public.classes c on c.id = e.class_id
  where public.is_staff()
  group by s.id, s.name, s.school, s.grade, s.status
  order by s.name
$$;

revoke all on function public.staff_student_roster() from public;
grant execute on function public.staff_student_roster() to authenticated;
