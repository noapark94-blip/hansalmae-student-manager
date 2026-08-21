drop policy if exists family_special_read_own_receipts
  on public.family_special_lesson_report_reads;

create policy family_special_read_own_receipts
  on public.family_special_lesson_report_reads
  for select
  to authenticated
  using (viewer_profile_id = (select auth.uid()));
