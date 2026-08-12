create or replace function public.staff_register_student_with_guardian(
  p_name text,
  p_school text default null,
  p_grade text default null,
  p_phone text default null,
  p_status text default 'active',
  p_internal_note text default null,
  p_guardian_name text default null,
  p_guardian_phone text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  new_student public.students;
  new_guardian_id uuid;
begin
  if not public.is_staff() then
    raise exception 'staff access required';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'student name is required';
  end if;

  insert into public.students(name, school, grade, phone, status, internal_note)
  values (
    trim(p_name), nullif(trim(p_school), ''), nullif(trim(p_grade), ''),
    nullif(trim(p_phone), ''), coalesce(nullif(trim(p_status), ''), 'active'),
    nullif(trim(p_internal_note), '')
  )
  returning * into new_student;

  if nullif(trim(p_guardian_phone), '') is not null then
    insert into public.guardians(name, phone)
    values (coalesce(nullif(trim(p_guardian_name), ''), trim(p_name) || ' 보호자'), trim(p_guardian_phone))
    returning id into new_guardian_id;

    insert into public.student_guardians(student_id, guardian_id, relationship, is_primary)
    values (new_student.id, new_guardian_id, '학부모', true);
  end if;

  return jsonb_build_object(
    'id', new_student.id,
    'name', new_student.name,
    'school', new_student.school,
    'grade', new_student.grade,
    'status', new_student.status
  );
end;
$$;

grant execute on function public.staff_register_student_with_guardian(text,text,text,text,text,text,text,text) to authenticated;
grant insert on table public.guardians, public.student_guardians to authenticated;
