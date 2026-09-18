create or replace function public.staff_student_roster_with_contacts()
returns table(id uuid,name text,school text,grade text,status text,enrollments jsonb,phone text,"guardianPhones" text[])
language sql stable security definer set search_path=public
as $$
 select r.id,r.name,r.school,r.grade,r.status,r.enrollments,s.phone,
 coalesce((select array_agg(distinct g.phone) filter(where g.phone is not null) from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=r.id),array[]::text[])
 from public.staff_student_roster() r join public.students s on s.id=r.id
 where public.is_staff()
$$;
revoke all on function public.staff_student_roster_with_contacts() from public,anon;
grant execute on function public.staff_student_roster_with_contacts() to authenticated;
