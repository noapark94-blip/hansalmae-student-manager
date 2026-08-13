-- 숙제 결과 RLS 정책의 lesson_id 열 참조를 명확하게 지정합니다.

drop policy if exists "assigned_staff_read_homework_results" on public.lesson_homework_results;
drop policy if exists "assigned_staff_manage_homework_results" on public.lesson_homework_results;

create policy "assigned_staff_read_homework_results"
on public.lesson_homework_results for select to authenticated using (
  public.current_user_role() = 'admin' or exists (
    select 1
    from public.lessons l
    join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_homework_results.lesson_id
      and ct.profile_id = auth.uid()
  )
);

create policy "assigned_staff_manage_homework_results"
on public.lesson_homework_results for all to authenticated using (
  public.current_user_role() = 'admin' or exists (
    select 1
    from public.lessons l
    join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_homework_results.lesson_id
      and ct.profile_id = auth.uid()
  )
) with check (
  public.current_user_role() = 'admin' or exists (
    select 1
    from public.lessons l
    join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_homework_results.lesson_id
      and ct.profile_id = auth.uid()
  )
);

notify pgrst, 'reload schema';
