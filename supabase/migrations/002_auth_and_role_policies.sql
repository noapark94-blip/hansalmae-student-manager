-- 인증 사용자 프로필 자동 생성과 역할별 접근 정책

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, role, display_name)
  values (
    new.id,
    coalesce((new.raw_user_meta_data ->> 'role')::public.user_role, 'student'),
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer set search_path = public
as $$
  select coalesce(public.current_user_role() in ('admin', 'teacher'), false)
$$;

revoke all on function public.current_user_role() from public;
revoke all on function public.is_staff() from public;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.is_staff() to authenticated;

create policy "profiles_read_own_or_staff" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());
create policy "profiles_admin_update" on public.profiles
  for update to authenticated
  using (public.current_user_role() = 'admin')
  with check (public.current_user_role() = 'admin');

create policy "staff_manage_students" on public.students
  for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "student_read_self" on public.students
  for select to authenticated using (profile_id = auth.uid());

create policy "staff_manage_guardians" on public.guardians
  for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "guardian_read_self" on public.guardians
  for select to authenticated using (profile_id = auth.uid());
create policy "staff_manage_student_guardians" on public.student_guardians
  for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "family_read_student_guardians" on public.student_guardians
  for select to authenticated using (
    exists (select 1 from public.students s where s.id = student_id and s.profile_id = auth.uid())
    or exists (select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid())
  );

create policy "authenticated_read_teachers" on public.teachers for select to authenticated using (true);
create policy "staff_manage_teachers" on public.teachers for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "authenticated_read_classes" on public.classes for select to authenticated using (true);
create policy "staff_manage_classes" on public.classes for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "authenticated_read_schedules" on public.class_schedules for select to authenticated using (true);
create policy "staff_manage_schedules" on public.class_schedules for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "authenticated_read_schedule_exceptions" on public.schedule_exceptions for select to authenticated using (true);
create policy "staff_manage_schedule_exceptions" on public.schedule_exceptions for all to authenticated using (public.is_staff()) with check (public.is_staff());

create policy "staff_manage_enrollments" on public.enrollments for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "family_read_enrollments" on public.enrollments for select to authenticated using (
  exists (select 1 from public.students s where s.id = student_id and s.profile_id = auth.uid())
  or exists (
    select 1 from public.student_guardians sg
    join public.guardians g on g.id = sg.guardian_id
    where sg.student_id = enrollments.student_id and g.profile_id = auth.uid()
  )
);
create policy "staff_manage_lessons" on public.lessons for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "authenticated_read_lessons" on public.lessons for select to authenticated using (true);
create policy "staff_manage_attendance" on public.attendance for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "family_read_attendance" on public.attendance for select to authenticated using (
  exists (select 1 from public.students s where s.id = student_id and s.profile_id = auth.uid())
  or exists (
    select 1 from public.student_guardians sg
    join public.guardians g on g.id = sg.guardian_id
    where sg.student_id = attendance.student_id and g.profile_id = auth.uid()
  )
);

create policy "staff_manage_consultations" on public.consultations for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "authenticated_read_published_announcements" on public.announcements
  for select to authenticated using (published_at is not null or public.is_staff());
create policy "staff_manage_announcements" on public.announcements for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "staff_manage_message_logs" on public.message_logs for all to authenticated using (public.is_staff()) with check (public.is_staff());
