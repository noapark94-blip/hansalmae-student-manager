-- 시험 내용을 입력한 신규·수정 기록은 반드시 시험 종류를 포함해야 합니다.

alter table public.lesson_exam_results
  add constraint lesson_exam_results_require_exam_type
  check (
    (nullif(trim(exam_title),'') is null and score is null and nullif(trim(evaluation),'') is null and nullif(trim(feedback),'') is null)
    or nullif(trim(exam_type),'') is not null
  );

alter table public.teacher_special_lesson_exam_results
  add constraint special_lesson_exam_results_require_exam_type
  check (
    (nullif(trim(exam_title),'') is null and score is null and nullif(trim(evaluation),'') is null)
    or nullif(trim(exam_type),'') is not null
  );

alter table public.correction_reports
  add constraint correction_reports_require_exam_type
  check (
    (nullif(trim(exam_title),'') is null and exam_score is null and nullif(trim(evaluation),'') is null)
    or (
      exam_range like '[종류]%'
      and nullif(trim(replace(split_part(exam_range,E'\n',1),'[종류]','')),'') is not null
    )
  );
