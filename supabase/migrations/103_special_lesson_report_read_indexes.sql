create index if not exists idx_family_special_lesson_report_reads_student
  on public.family_special_lesson_report_reads (student_id);

create index if not exists idx_family_special_lesson_report_reads_viewer
  on public.family_special_lesson_report_reads (viewer_profile_id);
