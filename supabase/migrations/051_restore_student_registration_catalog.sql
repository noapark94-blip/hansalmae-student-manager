-- 일부 병합 과정에서 빠진 학생 등록용 클래스 카탈로그 함수를 복원합니다.
create or replace function public.staff_student_registration_classes()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when not public.is_staff() then '[]'::jsonb
    else coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'subject', coalesce(s.name, c.subject),
          'subject_id', c.subject_id,
          'room', c.room,
          'color', c.color,
          'active', c.active
        )
        order by coalesce(s.name, c.subject), c.name
      )
      from public.classes c
      left join public.academy_subjects s on s.id = c.subject_id
      where c.active
    ), '[]'::jsonb)
  end;
$$;

revoke all on function public.staff_student_registration_classes() from public;
grant execute on function public.staff_student_registration_classes() to authenticated;

-- PostgREST가 새 함수를 즉시 인식하도록 스키마 캐시 갱신을 요청합니다.
notify pgrst, 'reload schema';
