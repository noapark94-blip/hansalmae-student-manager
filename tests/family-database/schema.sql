-- Local PGlite fixture schema only. Never execute against the live project.
create table public.academy_subjects (
  "id" uuid,
  "name" text,
  "main_subject" text,
  "parent_id" uuid,
  "created_by" uuid,
  "active" boolean,
  "created_at" timestamp with time zone
);
create table public.attendance (
  "id" uuid,
  "lesson_id" uuid,
  "student_id" uuid,
  "status" text,
  "checked_at" timestamp with time zone,
  "note" text,
  "makeup_required" boolean,
  "late_minutes" integer,
  "absence_reason" text
);
create table public.class_daily_notices (
  "id" uuid,
  "class_id" uuid,
  "notice_date" date,
  "content" text,
  "created_by" uuid,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone
);
create table public.class_schedules (
  "id" uuid,
  "class_id" uuid,
  "weekday" smallint,
  "start_time" time without time zone,
  "end_time" time without time zone,
  "valid_from" date,
  "valid_until" date
);
create table public.class_teachers (
  "class_id" uuid,
  "profile_id" uuid
);
create table public.classes (
  "id" uuid,
  "name" text,
  "subject" text,
  "teacher_id" uuid,
  "room" text,
  "color" text,
  "active" boolean,
  "created_at" timestamp with time zone,
  "subject_id" uuid
);
create table public.correction_reports (
  "id" uuid,
  "assignment_id" uuid,
  "student_id" uuid,
  "correction_date" date,
  "start_time" time without time zone,
  "end_time" time without time zone,
  "subject" text,
  "attendance_status" text,
  "late_minutes" integer,
  "teacher_instruction" text,
  "exam_title" text,
  "exam_range" text,
  "exam_score" numeric,
  "exam_max_score" numeric,
  "evaluation" text,
  "homework_instruction" text,
  "homework_status" text,
  "homework_note" text,
  "correction_content" text,
  "assistant_feedback" text,
  "next_preparation" text,
  "published" boolean,
  "instruction_by" uuid,
  "recorded_by" uuid,
  "recorded_by_name" text,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone,
  "absence_reason" text,
  "correction_task_status" text,
  "correction_task_feedback" text,
  "last_edited_by" uuid,
  "last_edited_by_name" text
);
create table public.enrollments (
  "id" uuid,
  "student_id" uuid,
  "class_id" uuid,
  "status" text,
  "started_on" date,
  "ended_on" date,
  "monthly_fee" integer,
  "use_default_fee" boolean
);
create table public.guardians (
  "id" uuid,
  "profile_id" uuid,
  "name" text,
  "phone" text,
  "created_at" timestamp with time zone
);
create table public.lesson_exam_results (
  "id" uuid,
  "lesson_id" uuid,
  "student_id" uuid,
  "score" numeric(7,2),
  "max_score" numeric(7,2),
  "evaluation" text,
  "feedback" text,
  "created_by" uuid,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone,
  "exam_type" text,
  "exam_title" text
);
create table public.lesson_homework_results (
  "id" uuid,
  "lesson_id" uuid,
  "student_id" uuid,
  "status" text,
  "note" text,
  "created_by" uuid,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone,
  "assigned_homework" text,
  "inspection_status" text,
  "inspection_note" text,
  "lesson_content" text
);
create table public.lessons (
  "id" uuid,
  "class_id" uuid,
  "lesson_date" date,
  "starts_at" timestamp with time zone,
  "ends_at" timestamp with time zone,
  "room" text,
  "status" text,
  "exam_content" text,
  "lesson_content" text,
  "homework_content" text,
  "teacher_profile_id" uuid,
  "updated_at" timestamp with time zone,
  "revision_draft" jsonb,
  "revision_saved_at" timestamp with time zone,
  "revision_saved_by" uuid
);
create table public.profiles (
  "id" uuid,
  "role" text,
  "display_name" text,
  "phone" text,
  "created_at" timestamp with time zone,
  "is_active" boolean,
  "must_change_password" boolean
);
create table public.student_guardians (
  "student_id" uuid,
  "guardian_id" uuid,
  "relationship" text,
  "is_primary" boolean
);
create table public.student_schedule_assignments (
  "student_id" uuid,
  "class_schedule_id" uuid,
  "assigned_by" uuid,
  "created_at" timestamp with time zone
);
create table public.students (
  "id" uuid,
  "profile_id" uuid,
  "name" text,
  "school" text,
  "grade" text,
  "phone" text,
  "status" text,
  "internal_note" text,
  "created_at" timestamp with time zone,
  "pause_return_expected_on" date,
  "residence" text,
  "vehicle_pickup_location" text,
  "vehicle_dropoff_location" text,
  "vehicle_note" text
);
create table public.teacher_special_lesson_exam_results (
  "id" uuid,
  "session_id" uuid,
  "student_id" uuid,
  "exam_type" text,
  "exam_title" text,
  "score" numeric,
  "max_score" numeric,
  "evaluation" text,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone
);
create table public.teacher_special_lesson_students (
  "session_id" uuid,
  "student_id" uuid,
  "attendance_status" text,
  "late_minutes" integer,
  "absence_reason" text,
  "assigned_homework" text,
  "inspection_status" text,
  "inspection_note" text,
  "updated_at" timestamp with time zone,
  "lesson_content" text
);
create table public.teacher_special_lessons (
  "id" uuid,
  "teacher_profile_id" uuid,
  "lesson_date" date,
  "starts_at" time without time zone,
  "ends_at" time without time zone,
  "kind" text,
  "room" text,
  "note" text,
  "created_by" uuid,
  "created_at" timestamp with time zone,
  "updated_at" timestamp with time zone,
  "class_notice" text,
  "status" text,
  "subject_id" uuid,
  "reminder_enabled" boolean,
  "reminder_version" uuid,
  "reminder_recipient_ids" uuid[]
);