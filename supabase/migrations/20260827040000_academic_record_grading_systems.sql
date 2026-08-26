-- 중등 내신 성취도(A-E), 고등 내신 5등급, 모의고사 9등급을 구분합니다.

alter table public.student_academic_records
  add column achievement_level text
  check (achievement_level in ('A', 'B', 'C', 'D', 'E'));

alter table public.student_academic_records
  drop constraint student_academic_records_check2;

alter table public.student_academic_records
  add constraint student_academic_records_grading_system_check check (
    (
      record_type = 'school'
      and num_nonnulls(score, grade, rank, achievement_level) > 0
      and (grade is null or grade between 1 and 5)
      and not (grade is not null and achievement_level is not null)
    )
    or
    (
      record_type = 'mock'
      and achievement_level is null
      and num_nonnulls(score, standard_score, percentile, grade) > 0
    )
  );
