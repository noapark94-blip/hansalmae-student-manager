alter table public.student_academic_records
  add column if not exists school_grade text;

alter table public.student_academic_records
  drop constraint if exists student_academic_records_school_grade_check;

alter table public.student_academic_records
  add constraint student_academic_records_school_grade_check
  check (school_grade is null or school_grade in ('초6','중1','중2','중3','고1','고2','고3','재수','검정고시'));
