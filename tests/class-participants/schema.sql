-- Schema-only synthetic fixture; no production rows or credentials.

set check_function_bodies=off; create role anon; create role authenticated; create role service_role; create schema auth; create schema extensions;

create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);

create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;

create function auth.role() returns text language sql stable as $$select 'authenticated'::text$$;

create function auth.jwt() returns jsonb language sql stable as $$select '{}'::jsonb$$;

create type assignment_submission_status as enum('pending','submitted','reviewed');

create type attendance_status as enum('present','late','absent','excused');

create type enrollment_status as enum('active','paused','completed');

create type makeup_status as enum('scheduled','completed','cancelled');

create type user_role as enum('admin','teacher','student','guardian','assistant','manager','sub_admin');

create table correction_assignment_successors("prior_id" uuid,"next_id" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (prior_id));

create table correction_timetable_signals("key" text,"assignment_id" uuid,"changed_at" timestamp with time zone default clock_timestamp(),PRIMARY KEY (key));

create table student_grade_progression_cycles("academic_year" integer,"prepared_at" timestamp with time zone default now(),"prepared_by" uuid,"early_applied_at" timestamp with time zone,"completed_at" timestamp with time zone,PRIMARY KEY (academic_year));

create table student_grade_progression_items("id" uuid default gen_random_uuid(),"academic_year" integer,"student_id" uuid,"previous_grade" text,"previous_school" text,"proposed_grade" text,"proposed_school" text,"transition_kind" text,"decision" text,"approval_status" text default 'pending'::text,"approved_by" uuid,"approved_at" timestamp with time zone,"applied_at" timestamp with time zone,"created_at" timestamp with time zone default now(),UNIQUE (academic_year, student_id),PRIMARY KEY (id));

create table learning_report_publications("id" uuid default gen_random_uuid(),"student_id" uuid,"report_type" text,"period_start" date,"period_end" date,"teacher_comment" text,"snapshot" jsonb default '[]'::jsonb,"status" text default 'draft'::text,"created_by" uuid,"updated_by" uuid,"published_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (student_id, report_type, period_start));

create table learning_report_publication_reads("publication_id" uuid,"viewer_profile_id" uuid,"viewed_at" timestamp with time zone default now(),PRIMARY KEY (publication_id, viewer_profile_id));

create table enrollment_dedup_audit("duplicate_id" uuid,"retained_id" uuid,"original_row" jsonb,"archived_at" timestamp with time zone default now(),PRIMARY KEY (duplicate_id));

create table vehicle_schedule_notes("weekday" smallint,"note" text default ''::text,"updated_by" uuid,"updated_at" timestamp with time zone default now(),PRIMARY KEY (weekday));

create table guardian_link_requests("id" uuid default gen_random_uuid(),"profile_id" uuid,"guardian_name" text,"guardian_phone" text,"student_name" text,"school" text,"grade" text,"status" text default 'pending'::text,"matched_student_id" uuid,"reviewed_by" uuid,"reviewed_at" timestamp with time zone,"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (profile_id));

create table source_makeup_sessions("id" uuid default gen_random_uuid(),"source_type" text,"source_id" uuid,"student_id" uuid,"teacher_profile_id" uuid,"scheduled_at" timestamp with time zone,"ends_at" timestamp with time zone,"room" text,"status" makeup_status default 'scheduled'::makeup_status,"note" text,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (source_type, source_id, student_id));

create table tuition_payment_cancellations("payment_id" uuid,"charge_id" uuid,"payment_snapshot" jsonb,"reason" text,"cancelled_at" timestamp with time zone default now(),"cancelled_by" uuid,PRIMARY KEY (payment_id));

create table staff_live_signals("key" text,"topic" text,"entity_id" uuid,"class_id" uuid,"record_date" date,"changed_at" timestamp with time zone default clock_timestamp(),PRIMARY KEY (key));

create table academy_expenses("id" uuid,"spent_on" date,"category" text,"vendor" text,"amount" integer,"payment_method" text,"memo" text default ''::text,"receipt_path" text,"receipt_name" text,"version" integer default 1,"created_by" uuid,"updated_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"deleted_at" timestamp with time zone,"recurrence_id" uuid,"scheduled_month" date,PRIMARY KEY (id));

create table enrollments("id" uuid default gen_random_uuid(),"student_id" uuid,"class_id" uuid,"status" enrollment_status default 'active'::enrollment_status,"started_on" date default CURRENT_DATE,"ended_on" date,"monthly_fee" integer,"use_default_fee" boolean default true,PRIMARY KEY (id),UNIQUE (student_id, class_id, started_on));

create table teachers("id" uuid default gen_random_uuid(),"profile_id" uuid,"name" text,"subject" text,"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (profile_id));

create table schedule_exceptions("id" uuid default gen_random_uuid(),"class_id" uuid,"original_date" date,"kind" text,"replacement_date" date,"start_time" time without time zone,"end_time" time without time zone,"room" text,"note" text,PRIMARY KEY (id));

create table student_guardians("student_id" uuid,"guardian_id" uuid,"relationship" text,"is_primary" boolean default false,PRIMARY KEY (student_id, guardian_id));

create table profiles("id" uuid,"role" user_role,"display_name" text,"phone" text,"created_at" timestamp with time zone default now(),"is_active" boolean default true,"must_change_password" boolean default false,PRIMARY KEY (id));

create table classes("id" uuid default gen_random_uuid(),"name" text,"subject" text,"teacher_id" uuid,"room" text,"color" text default '#922D61'::text,"active" boolean default true,"created_at" timestamp with time zone default now(),"subject_id" uuid,PRIMARY KEY (id));

create table announcements("id" uuid default gen_random_uuid(),"class_id" uuid,"author_profile_id" uuid,"title" text,"body" text,"audience" text default 'class'::text,"published_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"student_id" uuid,"expires_at" timestamp with time zone,PRIMARY KEY (id));

create table message_logs("id" uuid default gen_random_uuid(),"student_id" uuid,"recipient_phone" text,"message_type" text,"body" text,"provider" text,"provider_message_id" text,"status" text default 'pending_approval'::text,"error_message" text,"sent_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"recipient_name" text,"announcement_id" uuid,"source_notification_id" uuid,"approved_by" uuid,"approved_at" timestamp with time zone,"cancelled_at" timestamp with time zone,"sending_at" timestamp with time zone,"delivery_attempts" integer default 0,"provider_group_id" text,"queue_batch_id" uuid,PRIMARY KEY (id),UNIQUE (source_notification_id));

create table consultations("id" uuid default gen_random_uuid(),"student_id" uuid,"teacher_id" uuid,"consulted_at" timestamp with time zone default now(),"internal_note" text,"guardian_summary" text,"student_summary" text,"next_contact_on" date,"created_at" timestamp with time zone default now(),"consultant_profile_id" uuid,"consultation_type" text default 'guardian'::text,PRIMARY KEY (id));

create table lessons("id" uuid default gen_random_uuid(),"class_id" uuid,"lesson_date" date,"starts_at" timestamp with time zone,"ends_at" timestamp with time zone,"room" text,"status" text default 'scheduled'::text,"exam_content" text,"lesson_content" text,"homework_content" text,"teacher_profile_id" uuid,"updated_at" timestamp with time zone default now(),"revision_draft" jsonb,"revision_saved_at" timestamp with time zone,"revision_saved_by" uuid,UNIQUE (class_id, starts_at),PRIMARY KEY (id));

create table students("id" uuid default gen_random_uuid(),"profile_id" uuid,"name" text,"school" text,"grade" text,"phone" text,"status" text default 'active'::text,"internal_note" text,"created_at" timestamp with time zone default now(),"pause_return_expected_on" date,"residence" text,"vehicle_pickup_location" text,"vehicle_dropoff_location" text,"vehicle_note" text,PRIMARY KEY (id),UNIQUE (profile_id));

create table attendance("id" uuid default gen_random_uuid(),"lesson_id" uuid,"student_id" uuid,"status" attendance_status,"checked_at" timestamp with time zone,"note" text,"makeup_required" boolean default false,"late_minutes" integer,"absence_reason" text,UNIQUE (lesson_id, student_id),PRIMARY KEY (id));

create table guardians("id" uuid default gen_random_uuid(),"profile_id" uuid,"name" text,"phone" text,"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (profile_id));

create table makeup_sessions("id" uuid default gen_random_uuid(),"attendance_id" uuid,"teacher_profile_id" uuid,"scheduled_at" timestamp with time zone,"ends_at" timestamp with time zone,"room" text,"status" makeup_status default 'scheduled'::makeup_status,"note" text,"created_at" timestamp with time zone default now(),UNIQUE (attendance_id),PRIMARY KEY (id));

create table class_teachers("class_id" uuid,"profile_id" uuid,PRIMARY KEY (class_id, profile_id));

create table correction_exceptions("id" uuid default gen_random_uuid(),"assignment_id" uuid,"week_start" date,"weekday" smallint,"slot_index" smallint,"note" text,UNIQUE (assignment_id, week_start),PRIMARY KEY (id));

create table vehicle_boardings("run_id" uuid,"student_id" uuid,PRIMARY KEY (run_id, student_id));

create table class_schedules("id" uuid default gen_random_uuid(),"class_id" uuid,"weekday" smallint,"start_time" time without time zone,"end_time" time without time zone,"valid_from" date,"valid_until" date,PRIMARY KEY (id));

create table vehicle_runs("id" uuid default gen_random_uuid(),"manager_profile_id" uuid,"weekday" smallint,"pickup_time" time without time zone,"pickup_location" text,"active" boolean default true,"created_at" timestamp with time zone default now(),"route_name" text default '기본 노선'::text,"direction" text default 'pickup'::text,"stop_order" smallint default 1,PRIMARY KEY (id));

create table assignments("id" uuid default gen_random_uuid(),"class_id" uuid,"title" text,"description" text,"due_at" timestamp with time zone,"created_by" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table assignment_submissions("id" uuid default gen_random_uuid(),"assignment_id" uuid,"student_id" uuid,"status" assignment_submission_status default 'pending'::assignment_submission_status,"submitted_at" timestamp with time zone,"feedback" text,"reviewed_at" timestamp with time zone,"reviewed_by" uuid,"updated_at" timestamp with time zone default now(),UNIQUE (assignment_id, student_id),PRIMARY KEY (id));

create table account_change_logs("id" uuid default gen_random_uuid(),"changed_by" uuid,"target_profile_id" uuid,"action" text,"details" jsonb default '{}'::jsonb,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table vehicle_run_exceptions("id" uuid default gen_random_uuid(),"run_id" uuid,"service_date" date,"kind" text,"pickup_time" time without time zone,"pickup_location" text,"note" text,"created_by" uuid default auth.uid(),"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (run_id, service_date));

create table student_status_history("id" uuid default gen_random_uuid(),"student_id" uuid,"previous_status" text,"new_status" text,"effective_on" date,"note" text,"changed_by" uuid,"created_at" timestamp with time zone default now(),"return_expected_on" date,PRIMARY KEY (id));

create table correction_slot_capacities("teacher_profile_id" uuid,"weekday" smallint,"slot_index" smallint,"capacity" smallint default 8,"updated_at" timestamp with time zone default now(),PRIMARY KEY (teacher_profile_id, weekday, slot_index));

create table attendance_status_history("id" uuid default gen_random_uuid(),"attendance_id" uuid,"previous_status" attendance_status,"next_status" attendance_status,"changed_by" uuid,"changed_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table family_notifications("id" uuid default gen_random_uuid(),"student_id" uuid,"recipient_profile_id" uuid,"event_key" text,"title" text,"body" text,"source_type" text,"source_id" uuid,"read_at" timestamp with time zone,"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (recipient_profile_id, event_key, source_type, source_id));

create table backup_audit_logs("id" uuid default gen_random_uuid(),"requested_by" uuid,"action" text,"section" text,"record_count" integer default 0,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table tuition_recurring_adjustments("id" uuid default gen_random_uuid(),"student_id" uuid,"kind" text,"label" text,"amount" integer default 0,"active" boolean default true,"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (student_id, kind));

create table bulk_account_import_logs("id" uuid default gen_random_uuid(),"requested_by" uuid,"file_name" text,"account_count" integer,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table tuition_charges("id" uuid default gen_random_uuid(),"student_id" uuid,"billing_month" date,"base_amount" integer default 0,"discount_amount" integer default 0,"additional_amount" integer default 0,"status" text default 'open'::text,"memo" text,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"line_items" jsonb default '[]'::jsonb,PRIMARY KEY (id),UNIQUE (student_id, billing_month));

create table bulk_import_logs("id" uuid default gen_random_uuid(),"requested_by" uuid,"file_name" text,"row_count" integer,"students_created" integer default 0,"classes_created" integer default 0,"enrollments_created" integer default 0,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table app_menu_settings("id" text,"layout" jsonb,"updated_at" timestamp with time zone default now(),"updated_by" uuid,PRIMARY KEY (id));

create table tuition_payments("id" uuid default gen_random_uuid(),"charge_id" uuid,"amount" integer,"payment_method" text,"paid_at" timestamp with time zone default now(),"memo" text,"recorded_by" uuid,"created_at" timestamp with time zone default now(),"allocations" jsonb default '[]'::jsonb,"method_detail" text,PRIMARY KEY (id));

create table academy_subjects("id" uuid default gen_random_uuid(),"name" text,"main_subject" text,"parent_id" uuid,"created_by" uuid,"active" boolean default true,"created_at" timestamp with time zone default now(),UNIQUE (main_subject, name),PRIMARY KEY (id));

create table lesson_homework_results("id" uuid default gen_random_uuid(),"lesson_id" uuid,"student_id" uuid,"status" text,"note" text,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"assigned_homework" text,"inspection_status" text,"inspection_note" text,"lesson_content" text,UNIQUE (lesson_id, student_id),PRIMARY KEY (id));

create table student_schedule_assignments("student_id" uuid,"class_schedule_id" uuid,"assigned_by" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (student_id, class_schedule_id));

create table academy_schools("id" uuid default gen_random_uuid(),"name" text,"active" boolean default true,"created_by" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table user_ui_preferences("profile_id" uuid,"menu_layout" jsonb,"class_order" uuid[] default '{}'::uuid[],"school_order" uuid[] default '{}'::uuid[],"updated_at" timestamp with time zone default now(),PRIMARY KEY (profile_id));

create table lesson_exam_results("id" uuid default gen_random_uuid(),"lesson_id" uuid,"student_id" uuid,"score" numeric(7,2),"max_score" numeric(7,2) default 100,"evaluation" text,"feedback" text,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"exam_type" text,"exam_title" text,PRIMARY KEY (id));

create table teacher_special_lessons("id" uuid default gen_random_uuid(),"teacher_profile_id" uuid,"lesson_date" date,"starts_at" time without time zone,"ends_at" time without time zone,"kind" text default 'makeup'::text,"room" text,"note" text,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"class_notice" text,"status" text default 'draft'::text,"subject_id" uuid,"reminder_enabled" boolean default false,"reminder_version" uuid default gen_random_uuid(),"reminder_recipient_ids" uuid[],PRIMARY KEY (id));

create table class_daily_notices("id" uuid default gen_random_uuid(),"class_id" uuid,"notice_date" date,"content" text,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),UNIQUE (class_id, notice_date),PRIMARY KEY (id));

create table class_makeup_attendees("class_id" uuid,"attendance_date" date,"student_id" uuid,"created_by" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (class_id, attendance_date, student_id));

create table exam_categories("id" uuid default gen_random_uuid(),"owner_profile_id" uuid,"name" text,"is_active" boolean default true,"sort_order" integer default 0,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table teacher_special_lesson_students("session_id" uuid,"student_id" uuid,"attendance_status" text,"late_minutes" integer,"absence_reason" text,"assigned_homework" text,"inspection_status" text,"inspection_note" text,"updated_at" timestamp with time zone default now(),"lesson_content" text,"lesson_kind" text,"makeup_source" text,"makeup_source_id" uuid,PRIMARY KEY (session_id, student_id));

create table tuition_fee_groups("id" uuid default gen_random_uuid(),"school_level" text,"name" text,"amount" integer,"active" boolean default true,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (school_level, name));

create table tuition_subject_group_mappings("subject_id" uuid,"school_level" text,"fee_group_id" uuid,PRIMARY KEY (subject_id, school_level));

create table family_learning_report_reads("id" uuid default gen_random_uuid(),"lesson_id" uuid,"student_id" uuid,"viewer_profile_id" uuid,"viewed_at" timestamp with time zone default now(),UNIQUE (lesson_id, student_id, viewer_profile_id),PRIMARY KEY (id));

create table tuition_combination_discounts("id" uuid default gen_random_uuid(),"school_level" text,"name" text,"amount" integer,"required_group_ids" uuid[],"active" boolean default true,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table announcement_read_receipts("announcement_id" uuid,"profile_id" uuid,"viewed_at" timestamp with time zone default now(),PRIMARY KEY (announcement_id, profile_id));

create table correction_schedule_exceptions("id" uuid default gen_random_uuid(),"assignment_id" uuid,"original_date" date,"kind" text,"target_date" date,"target_start_time" time without time zone,"target_end_time" time without time zone,"note" text,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table teacher_special_lesson_exam_results("id" uuid default gen_random_uuid(),"session_id" uuid,"student_id" uuid,"exam_type" text,"exam_title" text,"score" numeric,"max_score" numeric default 100,"evaluation" text,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (session_id, student_id));

create table correction_assignments("id" uuid default gen_random_uuid(),"student_id" uuid,"teacher_profile_id" uuid,"weekday" smallint,"slot_index" smallint,"valid_from" date default CURRENT_DATE,"valid_until" date,"created_at" timestamp with time zone default now(),"subject" text,"start_time" time without time zone,"end_time" time without time zone,"tutor_profile_id" uuid,"supervisor_profile_id" uuid,"note" text,"active" boolean default true,"created_by" uuid,"updated_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table correction_report_reads("report_id" uuid,"student_id" uuid,"viewer_profile_id" uuid,"viewed_at" timestamp with time zone default now(),PRIMARY KEY (report_id, viewer_profile_id));

create table vehicle_schedule_exclusions("student_id" uuid,"weekday" smallint,"direction" text,"created_by" uuid default auth.uid(),"created_at" timestamp with time zone default now(),PRIMARY KEY (student_id, weekday, direction));

create table vehicle_manual_assignments("student_id" uuid,"weekday" smallint,"direction" text,"vehicle_time" time without time zone,"created_by" uuid default auth.uid(),"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (student_id, weekday, direction));

create table family_special_lesson_report_reads("id" uuid default gen_random_uuid(),"session_id" uuid,"student_id" uuid,"viewer_profile_id" uuid,"viewed_at" timestamp with time zone default now(),UNIQUE (session_id, student_id, viewer_profile_id),PRIMARY KEY (id));

create table password_reset_requests("id" uuid default gen_random_uuid(),"profile_id" uuid,"requested_at" timestamp with time zone default now(),"status" text default 'pending'::text,"processed_at" timestamp with time zone,"processed_by" uuid,PRIMARY KEY (id));

create table account_invites("id" uuid default gen_random_uuid(),"code_hash" bytea,"code_hint" text,"role" user_role,"student_id" uuid,"created_by" uuid,"expires_at" timestamp with time zone,"used_at" timestamp with time zone,"used_by" uuid,"revoked_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"recipient_name" text,"recipient_phone" text,"sms_sent_at" timestamp with time zone,"sms_attempts" integer default 0,"sms_last_error" text,"sms_provider_message_id" text,UNIQUE (code_hash),PRIMARY KEY (id));

create table academy_expense_recurrences("id" uuid,"source_expense_id" uuid,"start_month" date,"repeat_day" integer,"active" boolean default true,"version" integer default 1,"updated_at" timestamp with time zone default now(),"updated_by" uuid,PRIMARY KEY (id),UNIQUE (source_expense_id));

create table account_recovery_challenges("id" uuid default gen_random_uuid(),"profile_id" uuid,"purpose" text,"phone_hash" text,"code_hash" text,"expires_at" timestamp with time zone,"attempts" integer default 0,"consumed_at" timestamp with time zone,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table account_help_requests("id" uuid default gen_random_uuid(),"requester_name" text,"account_type" text,"registered_phone" text,"reachable_phone" text,"reason" text,"profile_id" uuid,"status" text default 'pending'::text,"requested_at" timestamp with time zone default now(),"processed_at" timestamp with time zone,"processed_by" uuid,PRIMARY KEY (id));

create table vocabulary_word_sets("id" uuid default gen_random_uuid(),"name" text,"slug" text,"sort_order" integer default 0,"enabled" boolean default true,"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (slug));

create table vocabulary_words("id" bigint,"word_set_id" uuid,"day" integer,"word" text,"meaning" text,"example" text default ''::text,"translation" text default ''::text,"example_answer" text default ''::text,"sort_order" integer default 0,"created_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (word_set_id, day, word, sort_order));

create table class_lesson_roster_overrides("class_id" uuid,"lesson_date" date,"student_id" uuid,"added_by" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (class_id, lesson_date, student_id));

create table vocabulary_test_history("id" uuid default gen_random_uuid(),"title" text,"word_set_id" uuid,"word_set_name" text,"start_day" integer,"end_day" integer,"question_count" integer,"eng_to_kor_count" integer default 0,"kor_to_eng_count" integer default 0,"example_count" integer default 0,"created_by" uuid,"created_by_name" text,"test_drive_url" text,"answer_drive_url" text,"created_at" timestamp with time zone default now(),"question_snapshot" jsonb,PRIMARY KEY (id));

create table push_subscriptions("id" uuid default gen_random_uuid(),"profile_id" uuid,"endpoint" text,"p256dh" text,"auth" text,"user_agent" text,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (profile_id, endpoint));

create table learning_report_comment_reactions("comment_id" uuid,"profile_id" uuid,"reaction" text,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (comment_id, profile_id));

create table learning_report_comments("id" uuid default gen_random_uuid(),"lesson_id" uuid,"student_id" uuid,"author_profile_id" uuid,"parent_id" uuid,"body" text,"staff_read_at" timestamp with time zone,"family_read_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"deleted_at" timestamp with time zone,"special_lesson_id" uuid,PRIMARY KEY (id));

create table academic_calendar_events("id" uuid default gen_random_uuid(),"school" text,"grade" text,"category" text,"title" text,"starts_on" date,"ends_on" date,"starts_at" time without time zone,"ends_at" time without time zone,"class_id" uuid,"teacher_profile_id" uuid,"note" text,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"event_scope" text default 'school'::text,"contact_name" text,"contact_phone" text,"location" text,"status" text default 'scheduled'::text,"reminder_enabled" boolean default false,"reminder_version" uuid default gen_random_uuid(),"reminder_recipient_ids" uuid[],PRIMARY KEY (id));

create table student_academic_records("id" uuid default gen_random_uuid(),"student_id" uuid,"record_type" text,"academic_year" smallint,"semester" smallint,"exam_date" date,"exam_name" text,"subject" text,"score" numeric(6,2),"grade" smallint,"rank" integer,"cohort_size" integer,"school_average" numeric(6,2),"standard_score" numeric(7,2),"percentile" numeric(5,2),"note" text,"created_by" uuid default auth.uid(),"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"achievement_level" text,"school_grade" text,PRIMARY KEY (id));

create table push_delivery_log("notification_key" text,"profile_id" uuid,"created_at" timestamp with time zone default now(),PRIMARY KEY (notification_key, profile_id));

create table academy_account_balance("id" boolean default true,"amount" bigint,"checked_on" date,"version" integer default 1,"updated_at" timestamp with time zone default now(),"updated_by" uuid,PRIMARY KEY (id));

create table learning_alimtalk_deliveries("id" uuid default gen_random_uuid(),"student_id" uuid,"guardian_id" uuid,"report_type" text,"period_start" date,"period_end" date,"template_variables" jsonb default '{}'::jsonb,"status" text default 'draft'::text,"provider_message_id" text,"provider_group_id" text,"error_message" text,"created_by" uuid,"sent_at" timestamp with time zone,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"source_refs" jsonb,PRIMARY KEY (id),UNIQUE (student_id, guardian_id, report_type, period_start));

create table schedule_reminder_receipts("profile_id" uuid,"source" text,"source_id" uuid,"version" uuid,"shown_at" timestamp with time zone default now(),"read_at" timestamp with time zone,"dismissed_at" timestamp with time zone,PRIMARY KEY (profile_id, source, source_id, version));

create table record_work_requests("recipient_id" uuid,"work_date" date,"requested_at" timestamp with time zone default now(),"requested_by" uuid,PRIMARY KEY (recipient_id, work_date));

create table record_work_receipts("profile_id" uuid,"day" date,"phase" text,"shown_at" timestamp with time zone default now(),PRIMARY KEY (profile_id, day, phase));

create table correction_slot_assistants("weekday" smallint,"start_time" time without time zone,"assistant_profile_id" uuid,"created_by" uuid,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (weekday, start_time, assistant_profile_id));

create table learning_alimtalk_resend_attempts("id" uuid default gen_random_uuid(),"delivery_id" uuid,"status" text,"provider_message_id" text,"provider_group_id" text,"error_message" text,"created_by" uuid,"sent_at" timestamp with time zone,"created_at" timestamp with time zone default now(),PRIMARY KEY (id));

create table account_invite_students("invite_id" uuid,"student_id" uuid,"is_primary" boolean default false,"created_at" timestamp with time zone default now(),PRIMARY KEY (invite_id, student_id));

create table student_monthly_lesson_targets("student_id" uuid,"subject" text,"month" date,"target" integer,"version" integer default 1,"updated_at" timestamp with time zone default now(),PRIMARY KEY (student_id, subject, month));

create table correction_reports("id" uuid default gen_random_uuid(),"assignment_id" uuid,"student_id" uuid,"correction_date" date,"start_time" time without time zone,"end_time" time without time zone,"subject" text,"attendance_status" text default 'scheduled'::text,"late_minutes" integer,"teacher_instruction" text,"exam_title" text,"exam_range" text,"exam_score" numeric,"exam_max_score" numeric,"evaluation" text,"homework_instruction" text,"homework_status" text,"homework_note" text,"correction_content" text,"assistant_feedback" text,"next_preparation" text,"published" boolean default false,"instruction_by" uuid,"recorded_by" uuid,"recorded_by_name" text,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),"absence_reason" text,"correction_task_status" text,"correction_task_feedback" text,"last_edited_by" uuid,"last_edited_by_name" text,UNIQUE (assignment_id, correction_date, start_time),PRIMARY KEY (id));

create table class_lesson_revision_drafts("lesson_id" uuid,"payload" jsonb,"saved_at" timestamp with time zone default now(),"saved_by" uuid,PRIMARY KEY (lesson_id));

create table academic_calendar_categories("id" text,"scope" text,"label" text,"sort_order" integer default 0,"is_active" boolean default true,"created_at" timestamp with time zone default now(),"updated_at" timestamp with time zone default now(),PRIMARY KEY (id),UNIQUE (scope, label));

CREATE OR REPLACE FUNCTION public.is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((
    select role in ('admin','sub_admin','teacher','assistant','manager') and is_active
    from public.profiles
    where id = auth.uid()
  ), false)
$function$
;

CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS user_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select role from public.profiles where id = auth.uid() and is_active
$function$
;

CREATE OR REPLACE FUNCTION public.internal_class_record_lesson_id(p_class_id uuid, p_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select id from public.lessons where class_id=p_class_id and lesson_date=p_date
 order by (status='completed') desc, (status='cancelled'), starts_at, id limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.internal_student_has_class_record(p_student uuid, p_class uuid, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from lessons l where l.class_id=p_class and l.lesson_date=p_date and (
 exists(select 1 from attendance a where a.lesson_id=l.id and a.student_id=p_student)
 or exists(select 1 from lesson_homework_results h where h.lesson_id=l.id and h.student_id=p_student)
 or exists(select 1 from lesson_exam_results e where e.lesson_id=l.id and e.student_id=p_student)))
$function$
;

CREATE OR REPLACE FUNCTION public.student_uses_class_schedule(p_student_id uuid, p_schedule_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
      then exists(select 1 from public.student_schedule_assignments where student_id=p_student_id and class_schedule_id=p_schedule_id)
    else true
  end
$function$
;

CREATE OR REPLACE FUNCTION public.internal_student_regular_class_on(p_student uuid, p_class uuid, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from enrollments e join class_schedules cs on cs.class_id=e.class_id
 where e.student_id=p_student and e.class_id=p_class and e.status='active'
 and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)
 and cs.weekday=extract(isodow from p_date)::smallint
 and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
 and public.student_uses_class_schedule(p_student,cs.id))
$function$
;

CREATE OR REPLACE FUNCTION public.student_attends_class_on(p_student_id uuid, p_class_id uuid, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select public.internal_student_has_class_record(p_student_id,p_class_id,p_date)
 or exists(select 1 from class_makeup_attendees where student_id=p_student_id and class_id=p_class_id and attendance_date=p_date)
 or exists(select 1 from class_lesson_roster_overrides where student_id=p_student_id and class_id=p_class_id and lesson_date=p_date)
 or public.internal_student_regular_class_on(p_student_id,p_class_id,p_date)
 or exists(select 1 from schedule_exceptions x where x.class_id=p_class_id and x.replacement_date=p_date
   and x.kind in ('changed','makeup') and public.internal_student_regular_class_on(p_student_id,p_class_id,x.original_date))
$function$
;

CREATE OR REPLACE FUNCTION public.staff_class_exam_results(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 시험 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',s.school,'grade',s.grade,
    'exams',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',coalesce(r.max_score,100),'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.feedback,'')) order by r.created_at,r.id) from public.lesson_exam_results r where r.lesson_id=l.id and r.student_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select lesson.id from public.lessons lesson where lesson.class_id=p_class_id and lesson.lesson_date=p_date and lesson.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by lesson.starts_at limit 1) l on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_class_homework_results(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'lessonContent',coalesce(current_result.lesson_content,''),'assignedHomework',coalesce(current_result.assigned_homework,''),'inspectionStatus',coalesce(current_result.inspection_status,current_result.status,''),'inspectionNote',coalesce(current_result.inspection_note,current_result.note,''),'previousHomework',coalesce(previous_result.assigned_homework,'')) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1) lesson on true
  left join public.lesson_homework_results current_result on current_result.lesson_id=lesson.id and current_result.student_id=s.id
  left join lateral(select hr.assigned_homework from public.lesson_homework_results hr join public.lessons prior on prior.id=hr.lesson_id where prior.class_id=p_class_id and prior.lesson_date<p_date and hr.student_id=s.id and nullif(trim(hr.assigned_homework),'') is not null order by prior.lesson_date desc limit 1) previous_result on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_class_day(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('lessonId',l.id,'examContent',null,'lessonContent',null,'homeworkContent',null,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,
      'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note,
      'directAdded',exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id)
    ) order by s.name)
      from public.students s left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join lateral(select lesson.* from public.lessons lesson where lesson.class_id=c.id and lesson.lesson_date=p_date and lesson.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by lesson.starts_at limit 1) l on true where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_class_revision_draft(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 임시저장을 확인할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;

  select jsonb_build_object(
    'payload',d.payload,
    'savedAt',d.saved_at,
    'savedBy',coalesce(p.display_name,'담당 선생님')
  )
  into result
  from public.lessons l
  join public.class_lesson_revision_drafts d on d.lesson_id=l.id
  left join public.profiles p on p.id=d.saved_by
  where l.class_id=p_class_id and l.lesson_date=p_date and l.status='completed'
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1;

  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.staff_class_daily_notice(p_class_id uuid, p_date date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 반 공지를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  return (select content from public.class_daily_notices where class_id=p_class_id and notice_date=p_date);
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_class_lesson_content(p_class_id uuid, p_date date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 수업내용을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;
  return coalesce((select l.lesson_content from public.lessons l where l.class_id=p_class_id and l.lesson_date=p_date and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at limit 1),'');
end $function$
;

CREATE OR REPLACE FUNCTION public.class_edit_values(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare r jsonb; e jsonb; students jsonb:='{}'; v jsonb; k text;
begin
 for r in select value from jsonb_array_elements(coalesce(p_payload->'rows','[]')) loop
  e:=coalesce(r->'exam','{}');
  v:=jsonb_build_object('status',r->'status','lateMinutes',r->'lateMinutes',
    'absenceReason',coalesce(r->>'absenceReason',''),'note',coalesce(r->>'note',''));
  foreach k in array array['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] loop
   v:=v||jsonb_build_object(k,coalesce(r->>k,''));
  end loop;
  foreach k in array array['id','examType','examTitle','score','evaluation','feedback'] loop
   v:=v||jsonb_build_object('exam_'||k,coalesce(e->>k,''));
  end loop;
  v:=v||jsonb_build_object('exam_maxScore',coalesce(nullif(e->>'maxScore',''),'100'));
  students:=students||jsonb_build_object(r->>'studentId',v);
 end loop;
 return jsonb_build_object('notice',coalesce(p_payload->>'notice',''),'lessonContent',coalesce(p_payload->>'lessonContent',''),'students',students);
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_class_edit_snapshot(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ex jsonb; hw jsonb; dy jsonb; rv jsonb; nt text; lc text; payload jsonb; st text;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 확인할 수 있습니다.';
 end if;
 ex:=public.staff_class_exam_results(p_class_id,p_date);
 hw:=public.staff_class_homework_results(p_class_id,p_date);
 dy:=public.staff_class_day(p_class_id,p_date);
 rv:=public.staff_class_revision_draft(p_class_id,p_date);
 nt:=public.staff_class_daily_notice(p_class_id,p_date);
 lc:=public.staff_class_lesson_content(p_class_id,p_date);
 select case when status='completed' then 'completed' else 'draft' end into st from public.lessons
  where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1;
 select jsonb_build_object('notice',coalesce(nt,''),'lessonContent',coalesce(lc,''),'rows',coalesce(jsonb_agg(
  s||jsonb_build_object('studentId',s->>'id','status',case when s->>'status'='excused' then to_jsonb('absent'::text) else s->'status' end,
   'lessonContent',h->>'lessonContent','assignedHomework',h->>'assignedHomework','inspectionStatus',h->>'inspectionStatus','inspectionNote',h->>'inspectionNote',
   'exam',coalesce(e->'exams'->0,'{}'))),'[]')) into payload
 from jsonb_array_elements(coalesce(dy->'students','[]')) s
 left join jsonb_array_elements(coalesce(ex,'[]')) e on e->>'studentId'=s->>'id'
 left join jsonb_array_elements(coalesce(hw,'[]')) h on h->>'studentId'=s->>'id';
 -- A private revision is a complete existing draft; keep its original display semantics.
 return jsonb_build_object('exams',ex,'homework',hw,'day',dy,'notice',nt,'lessonContent',lc,'revision',rv,
  'state',coalesce(st,'draft'),'values',public.class_edit_values(coalesce(rv->'payload',payload)));
end $function$
;

CREATE OR REPLACE FUNCTION public.class_merge_edit_changes(p_current jsonb, p_changes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare c jsonb; path text[]; result jsonb:=p_current; seen text[]:='{}'; key text;
begin
 if jsonb_typeof(p_changes) is distinct from 'array' then raise exception '수정 항목을 확인해 주세요.'; end if;
 for c in select value from jsonb_array_elements(p_changes) loop
  if jsonb_typeof(c->'path') is distinct from 'array' or not(c?'before' and c?'value') then raise exception '수정 항목을 확인해 주세요.'; end if;
  select array_agg(value order by ord) into path from jsonb_array_elements_text(c->'path') with ordinality p(value,ord);
  if not ((array_length(path,1)=1 and path[1] in ('notice','lessonContent')) or
    (array_length(path,1)=3 and path[1]='students' and path[3] in ('status','lateMinutes','absenceReason','note','lessonContent','assignedHomework','inspectionStatus','inspectionNote','exam_id','exam_examType','exam_examTitle','exam_score','exam_maxScore','exam_evaluation'))) then
   raise exception '지원하지 않는 수정 항목입니다.';
  end if;
  key:=array_to_string(path,'/');
  if key=any(seen) then raise exception '중복 수정 항목입니다.'; end if;
  seen:=array_append(seen,key);
  if p_current#>path is null then raise exception '수업 명단이 변경됐습니다. 입력 내용을 보관한 뒤 최신 명단을 확인해 주세요.'; end if;
  if (p_current#>path) is distinct from (c->'before') and (p_current#>path) is distinct from (c->'value') then
   raise exception '다른 선생님이 먼저 같은 항목을 수정했습니다. 입력 내용은 유지됩니다. 최신 내용을 확인해 주세요. (%)',path[array_length(path,1)];
  end if;
  result:=jsonb_set(result,path,c->'value',false);
 end loop;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_clear_class_attendance(p_class_id uuid, p_date date, p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 수정할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  select l.id into v_lesson_id from public.lessons l where l.class_id=p_class_id and l.lesson_date=p_date and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at limit 1;
  if v_lesson_id is not null then delete from public.attendance a where a.lesson_id=v_lesson_id and a.student_id=p_student_id; end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_day(p_class_id uuid, p_date date, p_exam_content text, p_lesson_content text, p_homework_content text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare schedule_row public.class_schedules; result_id uuid; v_start time; v_end time; replacement_row public.schedule_exceptions;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
  select id into result_id from public.lessons
  where id=public.internal_class_record_lesson_id(p_class_id,p_date) for update;
  if result_id is not null then return result_id; end if;
  select * into replacement_row from public.schedule_exceptions where class_id=p_class_id and replacement_date=p_date and kind in ('changed','makeup') order by id limit 1;
  select * into schedule_row from public.class_schedules where class_id=p_class_id
    and weekday=extract(isodow from coalesce(replacement_row.original_date,p_date))::smallint
    and (valid_from is null or valid_from<=coalesce(replacement_row.original_date,p_date))
    and (valid_until is null or valid_until>=coalesce(replacement_row.original_date,p_date)) order by start_time limit 1;
  if replacement_row.id is null and exists(select 1 from public.schedule_exceptions where class_id=p_class_id and original_date=p_date and kind in ('cancelled','changed','makeup')) then schedule_row:=null; end if;
  if schedule_row.id is null and replacement_row.id is null and not exists(select 1 from public.class_makeup_attendees where class_id=p_class_id and attendance_date=p_date) then raise exception '정규 수업이 없는 날짜입니다. 보충 학생을 먼저 추가해 주세요.'; end if;
  v_start:=coalesce(replacement_row.start_time,schedule_row.start_time,'18:00'::time); v_end:=coalesce(replacement_row.end_time,schedule_row.end_time,'20:00'::time);
  insert into public.lessons(class_id,lesson_date,starts_at,ends_at,room,teacher_profile_id,updated_at)
  select c.id,p_date,((p_date+v_start) at time zone 'Asia/Seoul'),((p_date+v_end) at time zone 'Asia/Seoul'),coalesce(replacement_row.room,c.room),auth.uid(),now() from public.classes c where c.id=p_class_id
  on conflict(class_id,starts_at) do update set teacher_profile_id=auth.uid(),updated_at=now()
  returning id into result_id;
  return result_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_attendance(p_class_id uuid, p_date date, p_student_id uuid, p_status attendance_status, p_late_minutes integer DEFAULT NULL::integer, p_absence_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not public.student_attends_class_on(p_student_id,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생입니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  insert into public.attendance as attendance_record(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(v_lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then trim(p_absence_reason) end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_revision_draft(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid; v_saved_at timestamptz:=now();
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 임시저장할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(coalesce(p_payload->'rows','null'::jsonb))<>'array' then
    raise exception '임시저장할 수업 내용을 확인해 주세요.';
  end if;

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date and status='completed'
  and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at
  limit 1;
  if v_lesson_id is null then
    raise exception '완료된 수업만 수정 임시저장할 수 있습니다.';
  end if;

  insert into public.class_lesson_revision_drafts(lesson_id,payload,saved_at,saved_by)
  values(v_lesson_id,p_payload,v_saved_at,auth.uid())
  on conflict(lesson_id) do update
  set payload=excluded.payload,saved_at=excluded.saved_at,saved_by=excluded.saved_by;

  return v_saved_at;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_exam_results(p_class_id uuid, p_date date, p_results jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson uuid; v_student jsonb; v_exam jsonb; v_sid uuid; v_id uuid; v_score numeric; v_max numeric;
begin
  v_lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for v_student in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    v_sid:=(v_student->>'studentId')::uuid;
    if not public.student_attends_class_on(v_sid,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.'; end if;
    v_exam:=coalesce(v_student->'exams'->0,'{}'::jsonb);
    v_id:=nullif(v_exam->>'id','')::uuid; v_score:=nullif(v_exam->>'score','')::numeric; v_max:=coalesce(nullif(v_exam->>'maxScore','')::numeric,100);
    if v_max<=0 or (v_score is not null and (v_score<0 or v_score>v_max)) then raise exception '점수와 만점을 확인해 주세요.'; end if;
    if nullif(trim(v_exam->>'examType'),'') is null and nullif(trim(v_exam->>'examTitle'),'') is null and v_score is null and nullif(trim(v_exam->>'evaluation'),'') is null and nullif(trim(v_exam->>'feedback'),'') is null then continue; end if;
    if v_id is null then
      insert into public.lesson_exam_results(lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,feedback,created_by)
      values(v_lesson,v_sid,nullif(trim(v_exam->>'examType'),''),nullif(trim(v_exam->>'examTitle'),''),v_score,v_max,nullif(trim(v_exam->>'evaluation'),''),nullif(trim(v_exam->>'feedback'),''),auth.uid());
    else
      update public.lesson_exam_results set exam_type=nullif(trim(v_exam->>'examType'),''),exam_title=nullif(trim(v_exam->>'examTitle'),''),score=v_score,max_score=v_max,evaluation=nullif(trim(v_exam->>'evaluation'),''),feedback=nullif(trim(v_exam->>'feedback'),''),updated_at=now()
      where id=v_id and lesson_id=v_lesson and student_id=v_sid;
    end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_homework_results(p_class_id uuid, p_date date, p_results jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lesson uuid; item jsonb; sid uuid; individual_lesson text; assigned text; inspection text; inspection_memo text;
begin
  lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid;
    if not public.student_attends_class_on(sid,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.'; end if;
    individual_lesson:=nullif(trim(item->>'lessonContent'),''); assigned:=nullif(trim(item->>'assignedHomework'),''); inspection:=nullif(item->>'inspectionStatus',''); inspection_memo:=nullif(trim(item->>'inspectionNote'),'');
    if inspection is not null and inspection not in ('complete','partial','missing','excused') then raise exception '숙제 검사 상태를 확인해 주세요.'; end if;
    if individual_lesson is null and assigned is null and inspection is null and inspection_memo is null then delete from public.lesson_homework_results where lesson_id=lesson and student_id=sid;
    else insert into public.lesson_homework_results(lesson_id,student_id,lesson_content,assigned_homework,inspection_status,inspection_note,status,note,created_by) values(lesson,sid,individual_lesson,assigned,inspection,inspection_memo,inspection,inspection_memo,auth.uid())
      on conflict(lesson_id,student_id) do update set lesson_content=excluded.lesson_content,assigned_homework=excluded.assigned_homework,inspection_status=excluded.inspection_status,inspection_note=excluded.inspection_note,status=excluded.status,note=excluded.note,updated_at=now(); end if;
  end loop;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_daily_notice(p_class_id uuid, p_date date, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 반 공지를 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if nullif(trim(p_content),'') is null then delete from public.class_daily_notices where class_id=p_class_id and notice_date=p_date;
  else insert into public.class_daily_notices(class_id,notice_date,content,created_by) values(p_class_id,p_date,trim(p_content),auth.uid())
    on conflict(class_id,notice_date) do update set content=excluded.content,created_by=auth.uid(),updated_at=now(); end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_class_lesson_content(p_class_id uuid, p_date date, p_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수업내용을 저장할 수 있습니다.'; end if;
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  update public.lessons set lesson_content=nullif(trim(coalesce(p_content,'')),''),updated_at=now(),teacher_profile_id=auth.uid() where id=v_lesson_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_apply_class_revision_payload(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lesson_id uuid;
  v_row jsonb;
  v_exam jsonb;
  v_student_id uuid;
  v_status text;
  v_late_minutes integer;
  v_absence_reason text;
  v_missing_names text;
  v_exam_payload jsonb;
  v_homework_payload jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 반영할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(coalesce(p_payload->'rows', 'null'::jsonb)) <> 'array' then
    raise exception '반영할 수업 내용을 확인해 주세요.';
  end if;

  select l.id into v_lesson_id
  from public.lessons l
  where l.class_id = p_class_id
    and l.lesson_date = p_date
    and l.status = 'completed'
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1
  for update;

  if v_lesson_id is null then
    raise exception '완료된 수업의 수정 내용만 반영할 수 있습니다.';
  end if;

  select string_agg(s.name, ', ' order by s.name)
  into v_missing_names
  from public.students s
  where public.student_attends_class_on(s.id, p_class_id, p_date)
    and not exists (
      select 1
      from jsonb_array_elements(p_payload->'rows') as draft_rows(item)
      where nullif(item->>'studentId', '')::uuid = s.id
        and item->>'status' in ('present', 'late', 'absent')
    );

  if v_missing_names is not null then
    raise exception '출결 미입력 학생: %', v_missing_names;
  end if;

  for v_row in select value from jsonb_array_elements(p_payload->'rows')
  loop
    v_student_id := nullif(v_row->>'studentId', '')::uuid;
    if v_student_id is null
       or not public.student_attends_class_on(v_student_id, p_class_id, p_date) then
      raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.';
    end if;

    v_status := v_row->>'status';
    v_late_minutes := nullif(v_row->>'lateMinutes', '')::integer;
    v_absence_reason := nullif(trim(v_row->>'absenceReason'), '');
    if v_status = 'late' and coalesce(v_late_minutes, 0) < 1 then
      raise exception '지각 시간을 입력해 주세요.';
    end if;
    if v_status = 'absent' and v_absence_reason is null then
      raise exception '결석 사유를 입력해 주세요.';
    end if;

    perform public.staff_save_class_attendance(
      p_class_id,
      p_date,
      v_student_id,
      v_status::public.attendance_status,
      case when v_status = 'late' then v_late_minutes else null end,
      case when v_status = 'absent' then v_absence_reason else null end,
      nullif(trim(v_row->>'note'), '')
    );

    v_exam := coalesce(v_row->'exam', '{}'::jsonb);
    if nullif(trim(v_exam->>'examType'), '') is null
       and nullif(trim(v_exam->>'examTitle'), '') is null
       and nullif(v_exam->>'score', '') is null
       and nullif(trim(v_exam->>'evaluation'), '') is null then
      delete from public.lesson_exam_results
      where lesson_id = v_lesson_id and student_id = v_student_id;
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', item->>'studentId',
    'exams', jsonb_build_array(coalesce(item->'exam', '{}'::jsonb))
  )), '[]'::jsonb)
  into v_exam_payload
  from jsonb_array_elements(p_payload->'rows') as draft_rows(item);

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', item->>'studentId',
    'lessonContent', item->>'lessonContent',
    'assignedHomework', item->>'assignedHomework',
    'inspectionStatus', item->>'inspectionStatus',
    'inspectionNote', item->>'inspectionNote'
  )), '[]'::jsonb)
  into v_homework_payload
  from jsonb_array_elements(p_payload->'rows') as draft_rows(item);

  perform public.staff_save_class_exam_results(p_class_id, p_date, v_exam_payload);
  perform public.staff_save_class_homework_results(p_class_id, p_date, v_homework_payload);
  perform public.staff_save_class_daily_notice(p_class_id, p_date, coalesce(p_payload->>'notice', ''));
  perform public.staff_save_class_lesson_content(p_class_id, p_date, coalesce(p_payload->>'lessonContent', ''));

  update public.lessons
  set status = 'completed',
      revision_draft = null,
      revision_saved_at = null,
      revision_saved_by = null,
      updated_at = now()
  where id = v_lesson_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.staff_publish_class_revision(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  perform public.staff_apply_class_revision_payload(p_class_id,p_date,p_payload);

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date and status='completed'
  and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at
  limit 1;

  delete from public.class_lesson_revision_drafts where lesson_id=v_lesson_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.staff_set_class_lesson_state(p_class_id uuid, p_date date, p_state text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid; missing_names text;
begin
  if not public.is_staff() then raise exception '교직원만 수업 상태를 변경할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if p_state not in ('draft','completed') then raise exception '수업 상태를 확인해 주세요.'; end if;
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if p_state='completed' then
    select string_agg(s.name,', ' order by s.name) into missing_names from public.students s
    where public.student_attends_class_on(s.id,p_class_id,p_date)
      and not exists(select 1 from public.attendance a where a.lesson_id=v_lesson_id and a.student_id=s.id);
    if missing_names is not null then raise exception '출결 미입력 학생: %',missing_names; end if;
  end if;
  update public.lessons set status=p_state,updated_at=now() where id=v_lesson_id;
  return p_state;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_patch_class_record(p_class_id uuid, p_date date, p_changes jsonb, p_expected_state text, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare snap jsonb; current_values jsonb; merged jsonb; payload jsonb; r record; row_value jsonb; row_payload jsonb;
 rows_payload jsonb:='[]'; exams jsonb:='[]'; homework jsonb:='[]'; lesson_id uuid; before_row jsonb; k text; change_exam boolean; change_hw boolean;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 수정할 수 있습니다.';
 end if;
 if p_mode not in ('draft','complete','revision','publish','attendance') or p_mode is null then raise exception '저장 방식을 확인해 주세요.'; end if;
 -- Serialize only this class/date, including the first save when no lesson row exists.
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 select id into lesson_id from public.lessons where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1 for update;
 snap:=public.staff_class_edit_snapshot(p_class_id,p_date);
 if snap->>'state' is distinct from p_expected_state then raise exception '수업 완료 상태가 변경됐습니다. 입력 내용을 보관한 뒤 최신 기록을 확인해 주세요.'; end if;
 if (p_mode in ('revision','publish'))<>(p_expected_state='completed') then raise exception '수업 상태에 맞는 저장 버튼을 이용해 주세요.'; end if;
 current_values:=snap->'values';
 merged:=public.class_merge_edit_changes(current_values,p_changes);
 -- Identity is a dependency when changing an exam, not a user-editable field.
 if exists(select 1 from jsonb_array_elements(p_changes) c where c->'path'->>2='exam_id' and c->'before' is distinct from c->'value') then raise exception '시험 기록 식별자는 수정할 수 없습니다.'; end if;
 if p_mode='attendance' and exists(select 1 from jsonb_array_elements(p_changes) c where jsonb_array_length(c->'path')<>3 or c->'path'->>2 not in ('status','lateMinutes','absenceReason','note')) then raise exception '출결 항목만 저장할 수 있습니다.'; end if;
 for r in select * from jsonb_each(merged->'students') loop
  row_value:=r.value; before_row:=current_values->'students'->r.key;
  row_payload:=jsonb_build_object('studentId',r.key,'status',row_value->'status','lateMinutes',row_value->'lateMinutes',
   'absenceReason',row_value->>'absenceReason','note',row_value->>'note','lessonContent',row_value->>'lessonContent',
   'assignedHomework',row_value->>'assignedHomework','inspectionStatus',row_value->>'inspectionStatus','inspectionNote',row_value->>'inspectionNote',
   'exam',jsonb_build_object('id',nullif(row_value->>'exam_id',''),'examType',row_value->>'exam_examType','examTitle',row_value->>'exam_examTitle',
    'score',nullif(row_value->>'exam_score','')::numeric,'maxScore',coalesce(nullif(row_value->>'exam_maxScore','')::numeric,100),'evaluation',row_value->>'exam_evaluation','feedback',row_value->>'exam_feedback'));
  rows_payload:=rows_payload||jsonb_build_array(row_payload);
  if p_mode in ('revision','publish') or row_value=before_row then continue; end if;
  change_exam:=false; change_hw:=false;
  foreach k in array array['exam_examType','exam_examTitle','exam_score','exam_maxScore','exam_evaluation'] loop
   change_exam:=change_exam or row_value->k is distinct from before_row->k;
  end loop;
  foreach k in array array['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] loop
   change_hw:=change_hw or row_value->k is distinct from before_row->k;
  end loop;
  if change_exam then exams:=exams||jsonb_build_array(jsonb_build_object('studentId',r.key,'exams',jsonb_build_array(row_payload->'exam'))); end if;
  if change_hw then homework:=homework||jsonb_build_array(row_payload-'exam'); end if;
  if row_value->'status' is distinct from before_row->'status' or row_value->'lateMinutes' is distinct from before_row->'lateMinutes'
    or row_value->'absenceReason' is distinct from before_row->'absenceReason' or row_value->'note' is distinct from before_row->'note' then
   if row_value->>'status' is null then perform public.staff_clear_class_attendance(p_class_id,p_date,r.key::uuid);
   else perform public.staff_save_class_attendance(p_class_id,p_date,r.key::uuid,(row_value->>'status')::public.attendance_status,
    nullif(row_value->>'lateMinutes','')::integer,nullif(row_value->>'absenceReason',''),nullif(row_value->>'note','')); end if;
  end if;
 end loop;
 payload:=jsonb_build_object('notice',merged->>'notice','lessonContent',merged->>'lessonContent','rows',rows_payload);
 if p_mode='revision' then perform public.staff_save_class_revision_draft(p_class_id,p_date,payload);
 elsif p_mode='publish' then perform public.staff_publish_class_revision(p_class_id,p_date,payload);
 else
  if jsonb_array_length(exams)>0 then perform public.staff_save_class_exam_results(p_class_id,p_date,exams); end if;
  if jsonb_array_length(homework)>0 then perform public.staff_save_class_homework_results(p_class_id,p_date,homework); end if;
  if merged->'notice' is distinct from current_values->'notice' then perform public.staff_save_class_daily_notice(p_class_id,p_date,merged->>'notice'); end if;
  if merged->'lessonContent' is distinct from current_values->'lessonContent' then perform public.staff_save_class_lesson_content(p_class_id,p_date,merged->>'lessonContent'); end if;
  if p_mode<>'attendance' then perform public.staff_set_class_lesson_state(p_class_id,p_date,case when p_mode='complete' then 'completed' else 'draft' end); end if;
 end if;
 return public.staff_class_edit_snapshot(p_class_id,p_date);
end $function$
;

CREATE OR REPLACE FUNCTION public.internal_student_class_lesson_id(p_student uuid, p_class uuid, p_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select l.id from lessons l where l.class_id=p_class and l.lesson_date=p_date
 order by (exists(select 1 from attendance a where a.lesson_id=l.id and a.student_id=p_student)
 or exists(select 1 from lesson_homework_results h where h.lesson_id=l.id and h.student_id=p_student)
 or exists(select 1 from lesson_exam_results e where e.lesson_id=l.id and e.student_id=p_student)) desc,
 (l.status='completed') desc,(l.status='cancelled'),l.starts_at,l.id limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.internal_special_student_kind(p_session_id uuid, p_student_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select coalesce(a.lesson_kind,l.kind) from public.teacher_special_lessons l
 left join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id where l.id=p_session_id
$function$
;

CREATE OR REPLACE FUNCTION public.staff_monthly_lesson_coverage(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m date:=date_trunc('month',p_month)::date; last_day date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
 today date:=(now() at time zone 'Asia/Seoul')::date; role_name text:=public.current_user_role()::text; result jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or role_name='assistant' then raise exception '월별 수업 조회 권한이 없습니다.'; end if;
 if m is null or m<date '2000-01-01' or m>date '2100-12-01' then raise exception '조회할 월을 확인해 주세요.'; end if;
 with class_info as materialized (
  select c.*,coalesce(nullif(s.main_subject,''),nullif(s.name,''),c.subject) main_subject from classes c left join academy_subjects s on s.id=c.subject_id
 ), pairs as materialized (
  select distinct e.student_id,c.main_subject subject from enrollments e join class_info c on c.id=e.class_id
  where c.main_subject in ('국어','영어') and e.started_on<=last_day and (e.ended_on is null or e.ended_on>=m)
   and (e.status='active' or e.ended_on is not null)
   and (role_name='admin' or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select distinct a.student_id,c.main_subject from attendance a join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id
  where c.main_subject in ('국어','영어') and l.lesson_date between m and last_day
   and (role_name='admin' or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select distinct ss.student_id,coalesce(nullif(s.main_subject,''),s.name) from teacher_special_lessons l join teacher_special_lesson_students ss on ss.session_id=l.id join academy_subjects s on s.id=l.subject_id
  where coalesce(nullif(s.main_subject,''),s.name) in ('국어','영어') and l.lesson_date between m and last_day
   and (role_name='admin' or l.teacher_profile_id=auth.uid())

  union
  select cm.student_id,c.main_subject from class_makeup_attendees cm join class_info c on c.id=cm.class_id
  where c.main_subject in ('국어','영어') and cm.attendance_date between m and last_day
   and (role_name='admin' or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select a.student_id,c.main_subject from makeup_sessions ms join attendance a on a.id=ms.attendance_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id
  where c.main_subject in ('국어','영어') and (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and (role_name='admin' or ms.teacher_profile_id=auth.uid() or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select ms.student_id,coalesce(nullif(s.main_subject,''),s.name) from source_makeup_sessions ms join teacher_special_lessons l on l.id=ms.source_id and ms.source_type='special' join academy_subjects s on s.id=l.subject_id
  where coalesce(nullif(s.main_subject,''),s.name) in ('국어','영어') and (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and (role_name='admin' or ms.teacher_profile_id=auth.uid() or l.teacher_profile_id=auth.uid())
  union
  select t.student_id,t.subject from student_monthly_lesson_targets t where t.month=m and role_name='admin'
 ), days as (select generate_series(m::timestamp,last_day::timestamp,interval '1 day')::date d), planned as (
  select p.student_id,c.id class_id,p.subject,d.d class_date,cs.start_time start_time,cs.end_time end_time,'정규'::text kind
  from pairs p join enrollments e on e.student_id=p.student_id join class_info c on c.id=e.class_id and c.main_subject=p.subject and c.active
  join class_schedules cs on cs.class_id=c.id join days d on cs.weekday=extract(isodow from d.d)
  where (e.status='active' or e.ended_on is not null) and e.started_on<=d.d and (e.ended_on is null or e.ended_on>=d.d)
   and (cs.valid_from is null or cs.valid_from<=d.d) and (cs.valid_until is null or cs.valid_until>=d.d)
   and public.student_uses_class_schedule(p.student_id,cs.id)
   and not exists(select 1 from schedule_exceptions x where x.class_id=c.id and x.original_date=d.d and x.kind in ('cancelled','changed','makeup'))
  union all
  select p.student_id,c.id,p.subject,x.replacement_date,coalesce(x.start_time,cs.start_time),coalesce(x.end_time,cs.end_time),case when x.kind='makeup' then '보강' else '정규' end
  from pairs p join enrollments e on e.student_id=p.student_id join class_info c on c.id=e.class_id and c.main_subject=p.subject and c.active
  join schedule_exceptions x on x.class_id=c.id
  join lateral(select s.* from class_schedules s where s.class_id=c.id and s.weekday=extract(isodow from x.original_date)
   and (s.valid_from is null or s.valid_from<=x.original_date) and (s.valid_until is null or s.valid_until>=x.original_date)
   and public.student_uses_class_schedule(p.student_id,s.id) order by s.start_time limit 1) cs on true
  where x.kind in ('changed','makeup') and x.replacement_date between m and last_day
   and (e.status='active' or e.ended_on is not null) and e.started_on<=x.original_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
  union all
  select p.student_id,c.id,p.subject,cm.attendance_date,cs.start_time,cs.end_time,'보강'
  from pairs p join class_makeup_attendees cm on cm.student_id=p.student_id join class_info c on c.id=cm.class_id and c.main_subject=p.subject
  left join lateral(select * from class_schedules s where s.class_id=c.id order by (s.weekday=extract(isodow from cm.attendance_date)) desc,s.start_time limit 1) cs on true
  where cm.attendance_date between m and last_day
  union all
  select p.student_id,c.id,p.subject,r.lesson_date,cs.start_time,cs.end_time,'정규'
  from pairs p join class_lesson_roster_overrides r on r.student_id=p.student_id join class_info c on c.id=r.class_id and c.main_subject=p.subject
  left join lateral(select * from class_schedules s where s.class_id=c.id and s.weekday=extract(isodow from r.lesson_date) order by s.start_time limit 1) cs on true
  where r.lesson_date between m and last_day
 ), class_days as (
  select student_id,class_id,subject,class_date,min(start_time) start_time,max(end_time) end_time,
   case when bool_or(kind='보강') then '보강' else '정규' end kind from planned group by 1,2,3,4
  union
  select p.student_id,c.id,p.subject,l.lesson_date,null::time,null::time,'정규'
  from pairs p join attendance a on a.student_id=p.student_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id and c.main_subject=p.subject
  where l.lesson_date between m and last_day and not exists(select 1 from planned q where q.student_id=p.student_id and q.class_id=c.id and q.class_date=l.lesson_date)
 ), regular_events as (
  select 'regular:'||q.class_id||':'||q.class_date id,q.student_id,q.subject,q.class_date,
   coalesce(l.starts_at,(q.class_date+q.start_time) at time zone 'Asia/Seoul') starts_at,c.name title,q.kind,
   case when l.status='cancelled' then 'cancelled' when a.status in ('present','late') and q.class_date<=today then 'attended'
    when a.status in ('absent','excused') then 'absent'
    when coalesce(l.starts_at,(q.class_date+q.start_time) at time zone 'Asia/Seoul')>now() then 'planned' else 'unrecorded' end state
  from class_days q join class_info c on c.id=q.class_id
  left join lessons l on l.id=public.internal_student_class_lesson_id(q.student_id,q.class_id,q.class_date)
  left join attendance a on a.lesson_id=l.id and a.student_id=q.student_id
 ), special_events as (
  select 'special:'||l.id id,p.student_id,p.subject,l.lesson_date class_date,(l.lesson_date+l.starts_at) at time zone 'Asia/Seoul' starts_at,
   coalesce(s.name,p.subject) title,case when public.internal_special_student_kind(l.id,p.student_id)='makeup' then '보강' else '추가' end kind,
   case when l.status='cancelled' then 'cancelled' when ss.attendance_status in ('present','late') and l.lesson_date<=today then 'attended'
    when ss.attendance_status in ('absent','excused') then 'absent' when (l.lesson_date+l.starts_at) at time zone 'Asia/Seoul'>now() then 'planned' else 'unrecorded' end state
  from pairs p join teacher_special_lesson_students ss on ss.student_id=p.student_id join teacher_special_lessons l on l.id=ss.session_id
  join academy_subjects s on s.id=l.subject_id and coalesce(nullif(s.main_subject,''),s.name)=p.subject
  where l.lesson_date between m and last_day
 ), legacy_events as (
  select 'makeup:'||ms.id id,p.student_id,p.subject,(ms.scheduled_at at time zone 'Asia/Seoul')::date class_date,ms.scheduled_at starts_at,c.name title,'보강'::text kind,
   case when ms.status='cancelled' then 'cancelled' when ms.status='completed' and ms.scheduled_at<=now() then 'attended' when ms.scheduled_at>now() then 'planned' else 'unrecorded' end state
  from pairs p join attendance a on a.student_id=p.student_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id and c.main_subject=p.subject join makeup_sessions ms on ms.attendance_id=a.id
  where (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and not exists(select 1 from teacher_special_lesson_students ss where ss.student_id=p.student_id and ss.makeup_source='regular' and ss.makeup_source_id=a.id)
  union all
  select 'source-makeup:'||ms.id,p.student_id,p.subject,(ms.scheduled_at at time zone 'Asia/Seoul')::date,ms.scheduled_at,coalesce(s.name,p.subject),'보강',
   case when ms.status='cancelled' then 'cancelled' when ms.status='completed' and ms.scheduled_at<=now() then 'attended' when ms.scheduled_at>now() then 'planned' else 'unrecorded' end
  from pairs p join source_makeup_sessions ms on ms.student_id=p.student_id and ms.source_type='special'
  join teacher_special_lessons l on l.id=ms.source_id join academy_subjects s on s.id=l.subject_id and coalesce(nullif(s.main_subject,''),s.name)=p.subject
  where (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and not exists(select 1 from teacher_special_lesson_students ss where ss.student_id=p.student_id and ss.makeup_source='special' and ss.makeup_source_id=ms.source_id)
 ), events as materialized (select * from regular_events union all select * from special_events union all select * from legacy_events), rows as (
 select p.student_id,s.name,s.school,s.grade,p.subject,coalesce(t.target,case when p.subject='국어' then 8 else 12 end) target,t.version,
  count(*) filter(where ev.state='attended')::int attended,count(*) filter(where ev.state='planned')::int planned,
  count(*) filter(where ev.state='unrecorded')::int unrecorded,count(*) filter(where ev.state='absent')::int absent,
  coalesce(jsonb_agg(jsonb_build_object('id',ev.id,'date',ev.class_date,'time',to_char(ev.starts_at at time zone 'Asia/Seoul','HH24:MI'),'title',ev.title,'kind',ev.kind,'state',ev.state) order by ev.class_date,ev.starts_at,ev.id) filter(where ev.id is not null),'[]'::jsonb) events
 from pairs p join students s on s.id=p.student_id left join student_monthly_lesson_targets t on t.student_id=p.student_id and t.subject=p.subject and t.month=m
 left join events ev on ev.student_id=p.student_id and ev.subject=p.subject group by p.student_id,s.name,s.school,s.grade,p.subject,t.target,t.version
 )
 select jsonb_build_object('month',m,'today',today,'isAdmin',role_name='admin','items',coalesce(jsonb_agg(jsonb_build_object(
 'studentId',student_id,'name',name,'school',school,'grade',grade,'subject',subject,'target',target,'version',version,
 'enrollmentEnded',exists(select 1 from enrollments e join class_info c on c.id=e.class_id
   where e.student_id=rows.student_id and c.main_subject=rows.subject
    and e.ended_on<least(last_day,greatest(m,today)))
  and not exists(select 1 from enrollments e join class_info c on c.id=e.class_id
   where e.student_id=rows.student_id and c.main_subject=rows.subject
    and (e.status='active' or e.ended_on is not null) and e.started_on<=last_day
    and (e.ended_on is null or e.ended_on>=least(last_day,greatest(m,today)))),
 'attended',attended,'planned',planned,'unrecorded',unrecorded,'absent',absent,'events',events) order by name,subject),'[]'::jsonb)) into result from rows;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.can_send_alimtalk()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((
    select role in ('admin','sub_admin') and is_active
    from public.profiles
    where id = auth.uid()
  ), false)
$function$
;

CREATE OR REPLACE FUNCTION public.internal_alimtalk_report_sources(p_student_ids uuid[], p_from date, p_to date)
 RETURNS TABLE(student_id uuid, lessons jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with regular_rows as (
 select a.student_id,jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'source', case when exists(select 1 from public.class_makeup_attendees ma where ma.student_id=a.student_id and ma.class_id=c.id and ma.attendance_date=l.lesson_date) then 'makeup' else 'regular' end,
      'lessonContent', coalesce(hr.lesson_content, ''),
      'homeworkContent', coalesce(hr.assigned_homework, ''),
      'examContent', coalesce(l.exam_content, ''),
      'attendance', case when a.id is null then null else jsonb_build_object(
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'absenceReason', coalesce(a.absence_reason, ''),
        'note', coalesce(a.note, '')
      ) end,
      'homeworkResult', case
        when hr.id is null or (
          nullif(trim(coalesce(hr.status, '')), '') is null
          and nullif(trim(coalesce(hr.note, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_status, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_note, '')), '') is null
        ) then null
        else jsonb_build_object(
          'status', coalesce(nullif(hr.inspection_status, ''), hr.status, ''),
          'note', coalesce(nullif(hr.inspection_note, ''), hr.note, '')
        )
      end,
      'exams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', er.id,
          'examType', coalesce(er.exam_type, ''),
          'examTitle', coalesce(er.exam_title, ''),
          'score', er.score,
          'maxScore', coalesce(er.max_score, 100),
          'percent', case when er.score is null or coalesce(er.max_score, 0) <= 0 then null else round(er.score / er.max_score * 100, 1) end,
          'evaluation', coalesce(er.evaluation, ''),
          'feedback', coalesce(er.feedback, '')
        ) order by er.created_at, er.id)
        from (
          -- Match staff_class_exam_results -> exams[0], the editable exam.
          -- Later duplicate inserts are historical artifacts, not additional exams.
          select current_exam.* from public.lesson_exam_results current_exam
          where current_exam.lesson_id=l.id and current_exam.student_id=a.student_id
          order by current_exam.created_at,current_exam.id limit 1
        ) er
        where (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text sort_time,
 row_number() over(partition by a.student_id order by l.lesson_date desc,l.starts_at desc) rn
 from public.lessons l join public.classes c on c.id=l.class_id
 join public.attendance a on a.lesson_id=l.id and a.student_id=any(p_student_ids)
 left join public.profiles tp on tp.id=l.teacher_profile_id
 left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=a.student_id
 where l.status='completed' and l.lesson_date between p_from and p_to and l.lesson_date<=current_date
), special_rows as (
 select a.student_id,jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',case when public.internal_special_student_kind(l.id,a.student_id)='additional' then 'extra' else public.internal_special_student_kind(l.id,a.student_id) end,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=a.student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text sort_time
 from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=any(p_student_ids)
 join public.profiles p on p.id=l.teacher_profile_id left join public.academy_subjects s on s.id=l.subject_id
 where l.status='completed' and a.attendance_status is not null and l.lesson_date between p_from and p_to
), ranked as (
 select combined.*,row_number() over(partition by combined.student_id order by lesson_date desc,sort_time desc) rn
 from (select student_id,item,lesson_date,sort_time from regular_rows where rn<=500 union all select * from special_rows) combined
), all_rows as (
 select student_id,item,lesson_date,item->>'startsAt' starts_at from ranked where rn<=500
 union all
 select r.student_id,jsonb_build_object(
      'lessonId',r.id,'lessonDate',to_char(r.correction_date,'YYYY-MM-DD'),
      'startsAt',to_char(r.correction_date,'YYYY-MM-DD')||'T'||r.start_time::text||'+09:00',
      'classId',r.assignment_id,'className','첨삭','subject',r.subject,'source','correction','room',null,
      'teacherName',coalesce(r.recorded_by_name,'담당 선생님'),'lessonContent',coalesce(r.correction_content,''),
      'homeworkContent',coalesce(r.next_preparation,r.homework_instruction,''),'examContent',coalesce(r.exam_range,''),
      'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),
      'attendance',jsonb_build_object('status',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason','','note',coalesce(r.assistant_feedback,'')),
      'homeworkResult',case when r.homework_status is null then null else jsonb_build_object('status',r.homework_status,'note',coalesce(r.homework_note,'')) end,
      'exams',case when r.exam_title is null and r.exam_score is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'id',r.id,
        'examType',case when coalesce(r.exam_range,'') like '[종류]%' then coalesce(nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),''),'첨삭 평가') else '첨삭 평가' end,
        'examTitle',coalesce(r.exam_title,''),'score',r.exam_score,'maxScore',coalesce(r.exam_max_score,100),
        'percent',case when r.exam_score is null or coalesce(r.exam_max_score,0)<=0 then null else round(r.exam_score/r.exam_max_score*100,1) end,
        'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.teacher_instruction,''))) end
    ) item,r.correction_date,r.start_time::text
 from public.correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
 where r.student_id=any(p_student_ids) and r.correction_date between p_from and p_to and r.published
)
select all_rows.student_id,jsonb_agg(item order by lesson_date,starts_at) from all_rows group by all_rows.student_id;
$function$
;

CREATE OR REPLACE FUNCTION public.staff_alimtalk_ready_students(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.can_send_alimtalk() then raise exception '관리자만 알림톡 발송 대상을 확인할 수 있습니다.'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 then raise exception '발송 기간을 확인해 주세요.'; end if;

  with days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,'regular:'||cs.class_id||':'||d.occurrence_date||':'||cs.start_time expected_key,
      '정규수업' kind,c.name title,d.occurrence_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed') completed
    from days d join public.class_schedules cs on cs.weekday=extract(isodow from d.occurrence_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=d.occurrence_date) and (cs.valid_until is null or cs.valid_until>=d.occurrence_date)
    join public.classes c on c.id=cs.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active' and e.started_on<=d.occurrence_date and (e.ended_on is null or e.ended_on>=d.occurrence_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where public.student_attends_class_on(e.student_id, cs.class_id, d.occurrence_date)
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=d.occurrence_date and x.kind in ('cancelled','changed','makeup'))
  ),
  regular_replacements as (
    select distinct e.student_id,'regular:'||x.class_id||':'||x.replacement_date||':'||coalesce(x.start_time,cs.start_time) expected_key,
      case when x.kind='makeup' then '보강수업' else '변경수업' end,c.name,x.replacement_date,coalesce(x.start_time,cs.start_time),
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed')
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed')
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  scheduled_expected as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
  expected as (
    select * from scheduled_expected
    union all
    select a.student_id,'recorded-regular:'||l.id::text,'정규수업',c.name,l.lesson_date,
      (l.starts_at at time zone 'Asia/Seoul')::time,true
    from public.attendance a join public.lessons l on l.id=a.lesson_id
    join public.classes c on c.id=l.class_id
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where l.status='completed' and l.lesson_date between p_from and p_to
      and not exists(select 1 from scheduled_expected e
        where e.student_id=a.student_id and e.occurrence_date=l.lesson_date
        and (e.expected_key like 'regular:'||l.class_id::text||':'||l.lesson_date::text||':%'
          or e.expected_key='class-makeup:'||l.class_id::text||':'||l.lesson_date::text))
  ),
  completed_expected as (
    select * from expected where completed
  ),
  unresolved_expected as (
    select
      e.student_id,
      min(e.expected_key) expected_key,
      case when count(*)>1 then '교차수업' else min(e.kind) end kind,
      case when count(*)>1 then string_agg(distinct e.title,' / ' order by e.title) else min(e.title) end title,
      e.occurrence_date,
      e.start_time,
      false completed
    from expected e
    where not e.completed
      and not exists (
        select 1 from expected done
        where done.student_id=e.student_id
          and done.occurrence_date=e.occurrence_date
          and done.start_time is not distinct from e.start_time
          and done.completed
      )
    group by e.student_id,e.occurrence_date,e.start_time
  ),
  resolved_expected as (
    select * from completed_expected
    union all
    select * from unresolved_expected
  ),
  readiness as materialized (
    select student_id,count(*)::integer expected_count,count(*) filter(where completed)::integer completed_count,
      coalesce(jsonb_agg(jsonb_build_object('kind',kind,'title',title,'date',occurrence_date,'time',to_char(start_time,'HH24:MI')) order by occurrence_date,start_time,title) filter(where not completed),'[]'::jsonb) missing_items
    from resolved_expected group by student_id
  ),
  report_sources as materialized (
    select * from public.internal_alimtalk_report_sources(array(select student_id from readiness),p_from,p_to)
  ),
  recipients as materialized (
    select distinct on(sg.student_id) sg.student_id,
      jsonb_build_object('guardianName',g.name,'maskedPhone',left(regexp_replace(g.phone,'[^0-9]','','g'),3)||'-****-'||right(regexp_replace(g.phone,'[^0-9]','','g'),4),'available',true) recipient
    from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
    where sg.student_id in (select student_id from readiness) and length(regexp_replace(coalesce(g.phone,''),'[^0-9]','','g')) between 10 and 11
    order by sg.student_id,sg.is_primary desc,g.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',coalesce(s.school,''),'grade',coalesce(s.grade,''),
    'expectedCount',r.expected_count,'completedCount',r.completed_count,'complete',r.completed_count=r.expected_count,'missingItems',r.missing_items,
    'lessons',coalesce(src.lessons,'[]'::jsonb),'recipient',coalesce(rec.recipient,jsonb_build_object('guardianName','','maskedPhone','','available',false))
  ) order by (r.completed_count=r.expected_count) desc,s.name,s.id),'[]'::jsonb) into result
  from readiness r join public.students s on s.id=r.student_id left join report_sources src on src.student_id=s.id left join recipients rec on rec.student_id=s.id where r.expected_count>0;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_claim_learning_alimtalk(p_student_id uuid, p_report_type text, p_period_start date, p_period_end date, p_lesson_summary text, p_attendance_summary text, p_learning_summary text)
 RETURNS TABLE(id uuid, recipient_phone text, guardian_name text, student_name text, template_variables jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare target_guardian public.guardians%rowtype; delivery_id uuid; student_label text; variables jsonb;
begin
  if not public.can_send_alimtalk() then raise exception '관리자만 알림톡을 발송할 수 있습니다.'; end if;
  if p_report_type not in ('daily','weekly') or p_period_end<p_period_start or p_period_end-p_period_start>6 then raise exception '발송 기간을 확인해 주세요.'; end if;
  if length(trim(coalesce(p_lesson_summary,''))) < 1 or length(trim(coalesce(p_attendance_summary,''))) < 1 or length(trim(coalesce(p_learning_summary,''))) < 1 then raise exception '수업·출결·학습 요약에 빈 항목이 있습니다. 내용을 확인해 주세요.'; end if;
  select g.* into target_guardian from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
  where sg.student_id=p_student_id and length(regexp_replace(coalesce(g.phone,''),'\D','','g')) between 10 and 11 order by sg.is_primary desc,g.created_at limit 1;
  if target_guardian.id is null then raise exception '발송 가능한 학부모 연락처가 없습니다.'; end if;
  select name into student_label from public.students where students.id=p_student_id;
  variables:=jsonb_build_object('studentName',student_label,'periodStart',p_period_start,'periodEnd',p_period_end,'lessonSummary',trim(p_lesson_summary),'attendanceSummary',trim(p_attendance_summary),'learningSummary',trim(p_learning_summary));
  insert into public.learning_alimtalk_deliveries(student_id,guardian_id,report_type,period_start,period_end,template_variables,status,created_by)
  values(p_student_id,target_guardian.id,p_report_type,p_period_start,p_period_end,variables,'sending',auth.uid())
  on conflict(student_id,guardian_id,report_type,period_start) do update set period_end=excluded.period_end,template_variables=excluded.template_variables,status='sending',error_message=null,updated_at=now(),created_by=auth.uid()
  where public.learning_alimtalk_deliveries.status in ('draft','failed') returning public.learning_alimtalk_deliveries.id into delivery_id;
  if delivery_id is null then raise exception '이미 발송했거나 현재 발송 중인 기록입니다.'; end if;
  return query select delivery_id,regexp_replace(target_guardian.phone,'\D','','g'),target_guardian.name,student_label,variables;
end $function$
;

CREATE OR REPLACE FUNCTION public.internal_class_current_exam_id(p_lesson uuid, p_student uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select id from lesson_exam_results where lesson_id=p_lesson and student_id=p_student order by created_at,id limit 1
$function$
;

CREATE OR REPLACE FUNCTION public.family_learning_reports(p_student_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; safe_limit integer; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select s.id into selected_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학습리포트만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.'; end if;
    end if;
  end if;
  if selected_id is null then return '[]'::jsonb; end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,10),30));
  select coalesce(jsonb_agg(report_row order by lesson_date desc,starts_at desc),'[]'::jsonb) into result from (
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',l.starts_at,'classId',c.id,'className',c.name,'subject',c.subject,'room',coalesce(l.room,c.room),'teacherName',coalesce(tp.display_name,'담당 선생님'),
      'lessonContent',coalesce(l.lesson_content,''),'classNotice',coalesce(n.content,''),'homeworkContent',coalesce(hr.assigned_homework,l.homework_content,''),'examContent',coalesce(l.exam_content,''),
      'attendance',case when a.id is null then null else jsonb_build_object('status',a.status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note',coalesce(a.note,'')) end,
      'homeworkResult',case when hr.id is null then null else jsonb_build_object('status',coalesce(hr.inspection_status,hr.status,''),'note',coalesce(hr.inspection_note,hr.note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)),'[]'::jsonb)
    ) report_row,l.lesson_date,l.starts_at
    from public.lessons l join public.classes c on c.id=l.class_id 
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
    left join public.class_daily_notices n on n.class_id=l.class_id and n.notice_date=l.lesson_date
    where l.status='completed' and (exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=selected_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)) or (l.status='completed' and a.id is not null)) and l.lesson_date<=current_date and (a.id is not null or hr.id is not null or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or exists(select 1 from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)))
    order by l.lesson_date desc,l.starts_at desc limit safe_limit
  ) reports;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.family_completed_learning_reports(p_student_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; safe_limit integer; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.';
  end if;
  if viewer_role='student' then
    select s.id into selected_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학습리포트만 확인할 수 있습니다.'; end if;
  else
    select s.id into selected_id from public.guardians g
    join public.student_guardians sg on sg.guardian_id=g.id
    join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and (p_student_id is null or s.id=p_student_id)
    order by sg.is_primary desc,s.name limit 1;
    if selected_id is null then raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.'; end if;
  end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,10),30));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (
    select item,lesson_date,starts_at from (
      select jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))) item,
        l.lesson_date,l.starts_at::text starts_at
      from jsonb_array_elements(coalesce(public.family_learning_reports(selected_id,30),'[]'::jsonb)) entry(item)
      join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
      left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
      where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
      union all
      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '보강' else '추가수업' end,
        'mainSubject',coalesce(sub.name,''),
        'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
        'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),
        'examContent','',
        'attendance',case when a.attendance_status is null then null else jsonb_build_object(
          'status',a.attendance_status,'lateMinutes',a.late_minutes,
          'absenceReason',coalesce(a.absence_reason,''),'note','') end,
        'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object(
          'status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
        'exams',coalesce((select jsonb_agg(jsonb_build_object(
          'id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
          'score',e.score,'maxScore',coalesce(e.max_score,100),
          'percent',case when e.score is null or coalesce(e.max_score,0)<=0 then null else round(e.score/e.max_score*100,1) end,
          'evaluation',coalesce(e.evaluation,''),'feedback',coalesce(e.evaluation,'')
        )) from public.teacher_special_lesson_exam_results e
          where e.session_id=l.id and e.student_id=selected_id),'[]'::jsonb)
      ) item,l.lesson_date,l.starts_at::text starts_at
      from public.teacher_special_lessons l
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
      left join public.academy_subjects sub on sub.id=l.subject_id
      left join public.profiles p on p.id=l.teacher_profile_id
      where l.status='completed' and l.lesson_date<=current_date
    ) combined order by lesson_date desc,starts_at desc limit safe_limit
  ) limited;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.internal_family_student_id(p_student_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 가족 대시보드를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select id into selected_id from public.students where profile_id=auth.uid();
    if p_student_id is not null and p_student_id is distinct from selected_id then raise exception '본인 학생 정보만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀만 확인할 수 있습니다.'; end if;
    end if;
  end if;

return selected_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.family_today_lessons(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid; today date := (now() at time zone 'Asia/Seoul')::date; result jsonb;
begin
  sid:=public.internal_family_student_id(p_student_id);
  if sid is null then return '[]'::jsonb; end if;
  with rows as (
    select 'regular:'||l.id::text id,'regular' kind,'정규수업' label,coalesce(c.subject,c.name) subject,to_char(l.starts_at at time zone 'Asia/Seoul','HH24:MI') start_time,to_char(l.ends_at at time zone 'Asia/Seoul','HH24:MI') end_time,coalesce(p.display_name,'') teacher_name,coalesce(l.room,c.room,'') room,a.status::text attendance_status
    from public.lessons l join public.classes c on c.id=l.class_id left join public.profiles p on p.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=sid where l.lesson_date=today and l.id=public.internal_student_class_lesson_id(sid,l.class_id,today) and (a.id is not null or (l.status<>'cancelled' and (
      exists(select 1 from public.schedule_exceptions x where x.class_id=c.id
        and x.kind in ('changed','makeup') and x.replacement_date=today
        and (x.start_time is null or x.start_time=(l.starts_at at time zone 'Asia/Seoul')::time)
        and public.student_attends_class_on(sid,c.id,x.original_date))
      or (
        public.student_attends_class_on(sid,c.id,today)
        and not exists(select 1 from public.schedule_exceptions x
          where x.class_id=c.id and x.original_date=today and x.kind in ('cancelled','changed','makeup'))
      )
    )))
    union all
    select 'special:'||l.id::text,'special',case public.internal_special_student_kind(l.id,sid) when 'makeup' then '보강' when 'extra' then '추가수업' when 'additional' then '추가수업' else '개별수업' end,coalesce(s.name,'과목 미지정'),to_char(l.starts_at,'HH24:MI'),to_char(l.ends_at,'HH24:MI'),coalesce(p.display_name,''),coalesce(l.room,''),ss.attendance_status
    from public.teacher_special_lessons l join public.teacher_special_lesson_students ss on ss.session_id=l.id and ss.student_id=sid left join public.academy_subjects s on s.id=l.subject_id left join public.profiles p on p.id=l.teacher_profile_id where l.lesson_date=today and coalesce(l.status,'scheduled')<>'cancelled'
    union all
    select 'correction:'||ca.id::text,'correction','첨삭',coalesce(ca.subject,'과목 미지정'),to_char(ca.start_time,'HH24:MI'),to_char(ca.end_time,'HH24:MI'),coalesce(p.display_name,''),'',cr.attendance_status
    from public.correction_assignments ca left join public.profiles p on p.id=coalesce(ca.tutor_profile_id,ca.teacher_profile_id) left join public.correction_reports cr on cr.assignment_id=ca.id and cr.student_id=sid and cr.correction_date=today and cr.start_time=ca.start_time
    where ca.student_id=sid and ca.active and ca.valid_from<=today and (ca.valid_until is null or ca.valid_until>=today) and ca.weekday=extract(isodow from today)::int and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=ca.id and x.original_date=today and x.kind in ('cancel','move'))
    union all
    select 'correction-move:'||x.id::text,'correction','첨삭',coalesce(ca.subject,'과목 미지정'),to_char(coalesce(x.target_start_time,ca.start_time),'HH24:MI'),to_char(coalesce(x.target_end_time,ca.end_time),'HH24:MI'),coalesce(p.display_name,''),'',cr.attendance_status
    from public.correction_schedule_exceptions x join public.correction_assignments ca on ca.id=x.assignment_id and ca.student_id=sid left join public.profiles p on p.id=coalesce(ca.tutor_profile_id,ca.teacher_profile_id) left join public.correction_reports cr on cr.assignment_id=ca.id and cr.student_id=sid and cr.correction_date=today and cr.start_time=coalesce(x.target_start_time,ca.start_time) where x.target_date=today and x.kind in ('move','extra')
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'label',label,'subject',subject,'startTime',start_time,'endTime',end_time,'teacherName',teacher_name,'room',room,'attendanceStatus',attendance_status) order by start_time,id),'[]'::jsonb) into result from rows;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.family_live_dashboard(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 가족 대시보드를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select id into selected_id from public.students where profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학생 정보만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀만 확인할 수 있습니다.'; end if;
    end if;
  end if;
  select jsonb_build_object(
    'role',viewer_role,
    'children',case when viewer_role='guardian' then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by sg.is_primary desc,s.name) from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid()),'[]'::jsonb) else coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade)) from public.students s where s.id=selected_id),'[]'::jsonb) end,
    'selectedStudent',(select jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) from public.students s where s.id=selected_id),
    'weekClasses',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) order by cs.weekday,cs.start_time) from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id where e.student_id=selected_id and e.status='active' and c.active and (not exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id) or exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id and a.class_schedule_id=cs.id)) and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
    'upcomingClasses',coalesce((select jsonb_agg(row_data order by class_date,start_time) from (select jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'classDate',days.class_date,'startTime',cs.start_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) row_data,days.class_date,cs.start_time from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id cross join lateral (select day::date class_date from generate_series(current_date,current_date+13,interval '1 day') day) days where e.student_id=selected_id and e.status='active' and c.active and (not exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id) or exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id and a.class_schedule_id=cs.id)) and cs.weekday=extract(isodow from days.class_date)::smallint and (cs.valid_from is null or cs.valid_from<=days.class_date) and (cs.valid_until is null or cs.valid_until>=days.class_date) and not exists(select 1 from public.schedule_exceptions se where se.class_id=c.id and se.original_date=days.class_date and se.kind='cancelled') order by days.class_date,cs.start_time limit 6) upcoming),'[]'::jsonb),
    'attendanceSummary',jsonb_build_object('total',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date),'present',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='present'),'late',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='late'),'absent',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='absent')),
    'recentAttendance',coalesce((select jsonb_agg(row_data order by lesson_date desc) from (select jsonb_build_object('id',a.id,'lessonDate',l.lesson_date,'className',c.name,'status',a.status,'note',a.note) row_data,l.lesson_date from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id where a.student_id=selected_id order by l.lesson_date desc limit 10) recent),'[]'::jsonb),
    'makeups',coalesce((select jsonb_agg(jsonb_build_object('id',ms.id,'className',c.name,'scheduledAt',ms.scheduled_at,'room',ms.room,'status',ms.status,'teacherName',p.display_name) order by ms.scheduled_at) from public.makeup_sessions ms join public.attendance a on a.id=ms.attendance_id join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.profiles p on p.id=ms.teacher_profile_id where a.student_id=selected_id and ms.status<>'cancelled' and ms.scheduled_at>=now()-interval '30 days'),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(row_data order by due_at) from (select jsonb_build_object('id',ass.id,'title',ass.title,'className',c.name,'dueAt',ass.due_at,'status',coalesce(sub.status,'pending'::public.assignment_submission_status),'feedback',sub.feedback) row_data,ass.due_at from public.assignments ass join public.classes c on c.id=ass.class_id left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=selected_id where exists(select 1 from public.enrollments e where e.class_id=ass.class_id and e.student_id=selected_id and e.status='active') order by (coalesce(sub.status,'pending'::public.assignment_submission_status)='reviewed'),ass.due_at limit 12) work),'[]'::jsonb),
    'announcements',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'body',a.body,'publishedAt',a.published_at,'authorName',coalesce(p.display_name,'한살매')) order by a.published_at desc) from public.announcements a left join public.profiles p on p.id=a.author_profile_id where a.published_at is not null and a.published_at<=now() and (a.expires_at is null or a.expires_at>now()) and (a.audience='all' or (a.audience='student' and a.student_id=selected_id) or (a.audience='class' and exists(select 1 from public.enrollments e where e.student_id=selected_id and e.class_id=a.class_id and e.status='active'))) limit 10),'[]'::jsonb),
    'consultations',coalesce((select jsonb_agg(jsonb_build_object('id',con.id,'consultedAt',con.consulted_at,'type',con.consultation_type,'consultantName',coalesce(p.display_name,t.name,'담당 선생님'),'summary',case when viewer_role='student' then con.student_summary else con.guardian_summary end,'nextContactOn',con.next_contact_on) order by con.consulted_at desc) from public.consultations con left join public.profiles p on p.id=con.consultant_profile_id left join public.teachers t on t.id=con.teacher_id where con.student_id=selected_id and (case when viewer_role='student' then con.student_summary else con.guardian_summary end) is not null limit 10),'[]'::jsonb)
  ) into result;
  return result;
end
$function$
;

CREATE OR REPLACE FUNCTION public.family_learning_calendar_schedule(p_student_id uuid DEFAULT NULL::uuid, p_month date DEFAULT (date_trunc('month'::text, timezone('Asia/Seoul'::text, now())))::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  base jsonb;
  sid uuid;
  month_start date := date_trunc('month', p_month)::date;
  month_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  result jsonb;
begin
  base := public.family_live_dashboard(p_student_id);
  sid := nullif(base->'selectedStudent'->>'id', '')::uuid;
  if sid is null then return '[]'::jsonb; end if;

  with recursive month_days as (
    select month_start as class_date
    union all
    select class_date + 1 from month_days where class_date < month_end
  ), saved_source as (
    select l.*,a.status::text attendance_status,c.name,c.subject,c.room class_room
    from lessons l join classes c on c.id=l.class_id
    left join attendance a on a.lesson_id=l.id and a.student_id=sid
    where l.lesson_date between month_start and month_end and l.lesson_date<=(now() at time zone 'Asia/Seoul')::date
      and public.internal_student_has_class_record(sid,l.class_id,l.lesson_date)
      and l.id=public.internal_student_class_lesson_id(sid,l.class_id,l.lesson_date)
  ), saved_regular as (
    select 'regular-saved:'||id::text id,lesson_date class_date,
      (starts_at at time zone 'Asia/Seoul')::time start_time,(ends_at at time zone 'Asia/Seoul')::time end_time,
      'regular'::text kind,'정규수업'::text label,name title,subject,coalesce(room,class_room,'') room,
      case when status='cancelled' then 'cancelled' else 'scheduled' end state,attendance_status
    from saved_source
  ), regular_base as (
    select
      'regular:' || cs.id::text || ':' || d.class_date::text as id,
      d.class_date, cs.start_time, cs.end_time, 'regular'::text as kind,
      '정규수업'::text as label, c.name as title, c.subject,
      coalesce(c.room, '') as room, 'scheduled'::text as state, null::text as attendance_status
    from month_days d
    join public.class_schedules cs on cs.weekday = extract(isodow from d.class_date)::smallint
      and (cs.valid_from is null or cs.valid_from <= d.class_date)
      and (cs.valid_until is null or cs.valid_until >= d.class_date)
    join public.classes c on c.id = cs.class_id and c.active
    join public.enrollments e on e.class_id = c.id and e.student_id = sid
      and e.status = 'active' and e.started_on <= d.class_date
      and (e.ended_on is null or e.ended_on >= d.class_date)
    where not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=d.class_date)
      and (not exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid)
      or exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid and ssa.class_schedule_id = cs.id))
      and not exists (
        select 1 from public.schedule_exceptions x
        where x.class_id = c.id and x.original_date = d.class_date
          and x.kind in ('cancelled', 'changed', 'makeup')
      )
  ), regular_replacements as (
    select
      'regular-change:' || x.id::text as id, x.replacement_date as class_date,
      coalesce(x.start_time, cs.start_time) as start_time, coalesce(x.end_time, cs.end_time) as end_time,
      case when x.kind = 'makeup' then 'makeup' else 'regular' end as kind,
      case when x.kind = 'makeup' then '보강' else '변경수업' end as label,
      c.name as title, c.subject, coalesce(x.room, c.room, '') as room,
      'scheduled'::text as state, null::text as attendance_status
    from public.schedule_exceptions x
    join public.classes c on c.id = x.class_id and c.active
    join public.enrollments e on e.class_id = c.id and e.student_id = sid and e.status = 'active'
    left join lateral (
      select s.start_time, s.end_time from public.class_schedules s
      where s.class_id = c.id and s.weekday=extract(isodow from x.original_date)::smallint
        and (s.valid_from is null or s.valid_from<=x.original_date) and (s.valid_until is null or s.valid_until>=x.original_date)
        and public.student_uses_class_schedule(sid,s.id) order by s.start_time limit 1
    ) cs on true
    where x.replacement_date between month_start and month_end
      and x.kind in ('changed', 'makeup')
      and public.internal_student_regular_class_on(sid,c.id,x.original_date)
      and not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=x.replacement_date)
      and e.started_on <= x.replacement_date
      and (e.ended_on is null or e.ended_on >= x.replacement_date)
  ), correction_base as (
    select
      'correction:' || a.id::text || ':' || d.class_date::text as id,
      d.class_date, a.start_time, a.end_time, 'correction'::text as kind,
      '첨삭'::text as label, coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject, ''::text as room,
      'scheduled'::text as state, null::text as attendance_status
    from month_days d
    join public.correction_assignments a on a.student_id = sid and a.active
      and a.weekday = extract(isodow from d.class_date)::smallint
      and a.valid_from <= d.class_date and (a.valid_until is null or a.valid_until >= d.class_date)
    where not exists (
      select 1 from public.correction_schedule_exceptions x
      where x.assignment_id = a.id and x.original_date = d.class_date and x.kind in ('move', 'cancel')
    )
  ), correction_changes as (
    select
      'correction-change:' || x.id::text as id, x.target_date as class_date,
      coalesce(x.target_start_time, a.start_time) as start_time,
      coalesce(x.target_end_time, a.end_time) as end_time,
      'correction'::text as kind,
      case when x.kind = 'extra' then '추가 첨삭' else '변경 첨삭' end as label,
      coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject, ''::text as room,
      'scheduled'::text as state, null::text as attendance_status
    from public.correction_schedule_exceptions x
    join public.correction_assignments a on a.id = x.assignment_id and a.student_id = sid
    where x.target_date between month_start and month_end and x.kind in ('move', 'extra')
  ), special as (
    select
      'special:' || l.id::text as id, l.lesson_date as class_date,
      l.starts_at as start_time, l.ends_at as end_time,
      case when public.internal_special_student_kind(l.id,sid) = 'makeup' then 'makeup' else 'extra' end as kind,
      case when public.internal_special_student_kind(l.id,sid) = 'makeup' then '보강' else '추가수업' end as label,
      coalesce(s.name, case when public.internal_special_student_kind(l.id,sid) = 'makeup' then '보강수업' else '추가수업' end) as title,
      coalesce(s.name, '개별수업') as subject, coalesce(l.room, '') as room,
      case when coalesce(l.status, 'scheduled') = 'cancelled' then 'cancelled' else 'scheduled' end as state,
      ss.attendance_status
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students ss on ss.session_id = l.id and ss.student_id = sid
    left join public.academy_subjects s on s.id = l.subject_id
    where l.lesson_date between month_start and month_end
  ), rows as (
    select * from saved_regular
    union all select * from regular_base
    union all select * from regular_replacements
    union all select * from correction_base
    union all select * from correction_changes
    union all select * from special
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'date', to_char(class_date, 'YYYY-MM-DD'),
    'startTime', to_char(start_time, 'HH24:MI'), 'endTime', to_char(end_time, 'HH24:MI'),
    'kind', kind, 'label', label, 'title', title, 'subject', subject,
    'room', room, 'state', state, 'attendanceStatus', attendance_status
  ) order by class_date, start_time, id), '[]'::jsonb) into result from rows;
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.family_exam_progress(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_student_id uuid; v_result jsonb;
begin
  v_role:=public.current_user_role();
  if v_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 시험 결과를 확인할 수 있습니다.'; end if;
  if v_role='student' then
    select s.id into v_student_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>v_student_id then raise exception '본인의 시험 결과만 확인할 수 있습니다.'; end if;
  else
    select s.id into v_student_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and (p_student_id is null or s.id=p_student_id) order by sg.is_primary desc,s.name limit 1;
    if p_student_id is not null and v_student_id is null then raise exception '연결된 자녀의 시험 결과만 확인할 수 있습니다.'; end if;
  end if;
  select coalesce(jsonb_agg(row_data order by lesson_date desc,created_at desc),'[]'::jsonb) into v_result from (
    select lesson_date,created_at,jsonb_build_object('id',id,'lessonDate',lesson_date,'className',class_name,'subject',subject_name,'mainSubject',main_subject,'examType',exam_type,'examTitle',exam_title,'itemType',item_type,'score',score,'maxScore',max_score,'percent',percent,'evaluation',evaluation,'feedback',feedback,'teacherName',teacher_name) row_data
    from (
      select r.id,r.created_at,l.lesson_date,c.name class_name,coalesce(subject.name,c.subject) subject_name,coalesce(subject.main_subject,c.subject) main_subject,
        coalesce(r.exam_type,'') exam_type,coalesce(r.exam_title,l.exam_content,'') exam_title,'regular'::text item_type,r.score,coalesce(nullif(r.max_score,0),100) max_score,
        case when r.score is null then null else round(r.score/coalesce(nullif(r.max_score,0),100)*100,1) end percent,coalesce(r.evaluation,'') evaluation,coalesce(r.feedback,'') feedback,coalesce(p.display_name,'담당 선생님') teacher_name
      from public.lesson_exam_results r join public.lessons l on l.id=r.lesson_id join public.classes c on c.id=l.class_id
      left join public.academy_subjects subject on subject.id=c.subject_id left join public.profiles p on p.id=coalesce(r.created_by,l.teacher_profile_id)
      where r.student_id=v_student_id and r.score is not null and l.status='completed'
        and l.id=public.internal_student_class_lesson_id(v_student_id,l.class_id,l.lesson_date)
        and r.id=public.internal_class_current_exam_id(l.id,v_student_id)
      union all
      select r.id,r.updated_at,l.lesson_date,case when public.internal_special_student_kind(l.id,v_student_id)='makeup' then '개별 보강' else '추가수업' end,
        coalesce(subject.name,case when public.internal_special_student_kind(l.id,v_student_id)='makeup' then '보강' else '추가수업' end),coalesce(subject.main_subject,subject.name,''),coalesce(r.exam_type,''),coalesce(r.exam_title,''),
        case when public.internal_special_student_kind(l.id,v_student_id)='makeup' then 'makeup' else 'extra' end,r.score,coalesce(nullif(r.max_score,0),100),
        case when r.score is null then null else round(r.score/coalesce(nullif(r.max_score,0),100)*100,1) end,coalesce(r.evaluation,''),coalesce(r.evaluation,''),coalesce(p.display_name,'담당 선생님')
      from public.teacher_special_lesson_exam_results r join public.teacher_special_lessons l on l.id=r.session_id
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=v_student_id
      left join public.academy_subjects subject on subject.id=l.subject_id left join public.profiles p on p.id=l.teacher_profile_id
      where r.student_id=v_student_id and l.status='completed' and r.score is not null
    ) all_exams order by lesson_date desc,created_at desc limit 120
  ) exam_rows;
  return v_result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_student_attendance_rates(p_days integer DEFAULT 30)
 RETURNS TABLE(student_id uuid, checked_count bigint, present_count bigint, late_count bigint, absent_count bigint, attendance_rate integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.student_id,
    count(*) filter (where a.status in ('present','late','absent')),
    count(*) filter (where a.status = 'present'),
    count(*) filter (where a.status = 'late'),
    count(*) filter (where a.status = 'absent'),
    round(100.0 * count(*) filter (where a.status = 'present') / nullif(count(*) filter (where a.status in ('present','late','absent')), 0))::integer
  from public.attendance a join public.lessons l on l.id = a.lesson_id
  where public.is_staff()
    and l.lesson_date between (now() at time zone 'Asia/Seoul')::date - greatest(1, least(coalesce(p_days, 30), 365)) + 1
      and (now() at time zone 'Asia/Seoul')::date
  group by a.student_id
$function$
;

CREATE OR REPLACE FUNCTION public.internal_special_makeup_board_overlay(p_board jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select jsonb_set(p_board,'{items}',coalesce(jsonb_agg(
 case when linked.session_id is null then item else item||jsonb_build_object(
 'linkedSpecialId',linked.session_id,'sessionId',linked.session_id,'teacherId',l.teacher_profile_id,'teacherName',p.display_name,
 'scheduledAt',(l.lesson_date+l.starts_at) at time zone 'Asia/Seoul','endsAt',(l.lesson_date+l.ends_at) at time zone 'Asia/Seoul','room',l.room,
 'status',case when l.status='completed' and linked.attendance_status in ('present','late') then 'completed' else 'scheduled' end) end
 order by ordinal),'[]'::jsonb))
 from jsonb_array_elements(p_board->'items') with ordinality rows(item,ordinal)
 left join public.teacher_special_lesson_students linked on item->>'recordKind'='absence' and linked.student_id=(item->>'studentId')::uuid
 and linked.makeup_source_id=(item->>'sourceId')::uuid
 and linked.makeup_source=case when item->>'source' in ('regular','class') then 'regular' when item->>'source'='correction' then 'correction' else 'special' end
 left join public.teacher_special_lessons l on l.id=linked.session_id left join public.profiles p on p.id=l.teacher_profile_id
 where not(item->>'recordKind'='schedule' and exists(select 1 from public.teacher_special_lesson_students a where a.session_id::text=item->>'sessionId' and a.student_id::text=item->>'studentId' and a.makeup_source_id is not null))
$function$
;

CREATE OR REPLACE FUNCTION public.absence_makeup_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role;
begin
  if not public.is_staff() or public.current_user_role()='assistant' then raise exception '결석·보강 조회 권한이 없습니다.'; end if;
  v_role:=public.current_user_role();
  return public.internal_special_makeup_board_overlay(jsonb_build_object(
    'isStaff',true,'role',v_role,
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','sub_admin','manager') and (v_role='admin' or p.id=auth.uid())),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(row_data order by sort_date desc,student_name) from (
      select jsonb_build_object('attendanceId',a.id,'sourceId',a.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',l.lesson_date,'attendanceNote',coalesce(a.absence_reason,a.note),'sessionId',ms.id,'teacherId',ms.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'note',ms.note,'source',case when exists(select 1 from public.class_makeup_attendees cm where cm.class_id=c.id and cm.student_id=st.id and cm.attendance_date=l.lesson_date) then 'class' else 'regular' end) row_data,
        coalesce(ms.scheduled_at,l.starts_at) sort_date,st.name student_name
      from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.students st on st.id=a.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join public.makeup_sessions ms on ms.attendance_id=a.id left join public.profiles tp on tp.id=ms.teacher_profile_id
      where (a.status='absent' or ms.id is not null) and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',r.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'첨삭수업'),'subjectId',scope.subject_id,'subjectName',coalesce(r.subject,'과목 미지정'),'missedDate',r.correction_date,'attendanceNote',r.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',sm.room,'status',sm.status,'note',sm.note,'source','correction') row_data,
        coalesce(sm.scheduled_at,((r.correction_date+r.start_time) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.correction_reports r join public.students st on st.id=r.student_id left join public.source_makeup_sessions sm on sm.source_type='correction' and sm.source_id=r.id and sm.student_id=r.student_id left join public.profiles tp on tp.id=sm.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name,c.subject_id from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (c.subject=r.subject or exists(select 1 from public.academy_subjects su where su.id=c.subject_id and su.name=r.subject)) order by c.name limit 1) scope on true
      where r.attendance_status='absent' and (v_role='admin' or exists(select 1 from public.correction_assignments ca where ca.id=r.assignment_id and (ca.tutor_profile_id=auth.uid() or ca.supervisor_profile_id=auth.uid())) or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,case when public.internal_special_student_kind(sl.id,ss.student_id)='makeup' then '개별 보강' else '추가수업' end),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',sl.lesson_date,'attendanceNote',ss.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',coalesce(tp.display_name,owner.display_name),'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',coalesce(sm.room,sl.room),'status',sm.status,'note',sm.note,'source',case when public.internal_special_student_kind(sl.id,ss.student_id)='makeup' then 'individual' else 'additional' end) row_data,
        coalesce(sm.scheduled_at,((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id left join public.academy_subjects sub on sub.id=sl.subject_id left join public.source_makeup_sessions sm on sm.source_type='special' and sm.source_id=sl.id and sm.student_id=st.id left join public.profiles tp on tp.id=sm.teacher_profile_id left join public.profiles owner on owner.id=sl.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where ss.attendance_status='absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',null,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',concat('class:',m.class_id,':',m.attendance_date),'teacherId',coalesce(l.teacher_profile_id,m.created_by),'teacherName',coalesce(lp.display_name,cp.display_name),'scheduledAt',coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')),'endsAt',coalesce(l.ends_at,((m.attendance_date+coalesce(sched.end_time,'20:00'::time)) at time zone 'Asia/Seoul')),'room',coalesce(l.room,c.room),'status',case when l.id is not null and (exists(select 1 from public.attendance ca where ca.lesson_id=l.id and ca.student_id=st.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null) then 'completed' else 'scheduled' end,'note',null,'source','class') row_data,
        coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.class_makeup_attendees m join public.classes c on c.id=m.class_id join public.students st on st.id=m.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join lateral (select lesson.* from public.lessons lesson where lesson.class_id=m.class_id and lesson.lesson_date=m.attendance_date order by lesson.starts_at limit 1) l on true left join lateral (select cs.start_time,cs.end_time from public.class_schedules cs where cs.class_id=m.class_id order by cs.start_time limit 1) sched on true left join public.profiles lp on lp.id=l.teacher_profile_id left join public.profiles cp on cp.id=m.created_by
      where not exists(select 1 from public.attendance ca where ca.lesson_id=l.id and ca.student_id=st.id and ca.status='absent') and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'개별 보강'),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',sl.id,'teacherId',sl.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul'),'endsAt',((sl.lesson_date+sl.ends_at) at time zone 'Asia/Seoul'),'room',sl.room,'status',case when sl.status='completed' then 'completed' else 'scheduled' end,'note',sl.note,'source','individual') row_data,
        ((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul') sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id join public.profiles tp on tp.id=sl.teacher_profile_id left join public.academy_subjects sub on sub.id=sl.subject_id left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where public.internal_special_student_kind(sl.id,ss.student_id)='makeup' and ss.attendance_status is distinct from 'absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
    ) rows),'[]'::jsonb)
  ));
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_record_worklist(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; uid uuid:=auth.uid(); admin boolean; today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and is_active and role in ('admin','sub_admin','teacher','assistant','manager')) then raise exception '교직원만 기록을 확인할 수 있습니다.';end if;
 admin:=public.current_user_role()='admin';
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 or p_to>today or p_from<today-30 then raise exception '최근 30일 내 최대 7일을 선택해 주세요.';end if;
  with days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,'regular:'||cs.class_id||':'||d.occurrence_date||':'||cs.start_time expected_key,
      '정규수업' kind,c.name title,d.occurrence_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed' and at.status::text in ('present','late','absent','excused')) completed
    from days d join public.class_schedules cs on cs.weekday=extract(isodow from d.occurrence_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=d.occurrence_date) and (cs.valid_until is null or cs.valid_until>=d.occurrence_date)
    join public.classes c on c.id=cs.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active' and e.started_on<=d.occurrence_date and (e.ended_on is null or e.ended_on>=d.occurrence_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where public.student_attends_class_on(e.student_id, cs.class_id, d.occurrence_date)
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=d.occurrence_date and x.kind in ('cancelled','changed','makeup'))
  ),
  regular_replacements as (
    select distinct e.student_id,'regular:'||x.class_id||':'||x.replacement_date||':'||coalesce(x.start_time,cs.start_time) expected_key,
      case when x.kind='makeup' then '보강수업' else '변경수업' end,c.name,x.replacement_date,coalesce(x.start_time,cs.start_time),
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where (cs.valid_from is null or cs.valid_from<=x.original_date) and (cs.valid_until is null or cs.valid_until>=x.original_date) and public.student_attends_class_on(e.student_id,x.class_id,x.original_date) and x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to and l.status<>'cancelled'
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  roster_additions as (
    select distinct o.student_id,'regular:'||o.class_id||':'||o.lesson_date||':'||coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time,'00:00'::time) expected_key,
      '정규수업',c.name,o.lesson_date,coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time),
      exists(select 1 from public.lessons ll join public.attendance a on a.lesson_id=ll.id and a.student_id=o.student_id where ll.class_id=o.class_id and ll.lesson_date=o.lesson_date and ll.status='completed' and a.status::text in ('present','late','absent','excused'))
    from public.class_lesson_roster_overrides o join public.classes c on c.id=o.class_id
    join public.students s on s.id=o.student_id and s.status in ('active','재원')
    left join public.lessons l on l.class_id=o.class_id and l.lesson_date=o.lesson_date
    left join public.class_schedules cs on cs.class_id=o.class_id and cs.weekday=extract(isodow from o.lesson_date)
    where o.lesson_date between p_from and p_to
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=o.class_id and x.original_date=o.lesson_date and x.kind in ('cancelled','changed','makeup'))
  ),
  scheduled_expected as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union select * from roster_additions
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 identified as (
 select distinct on (e.student_id,case when split_part(expected_key,':',1) in ('regular','class-makeup') then 'class:'||split_part(expected_key,':',2)||':'||occurrence_date else expected_key end) e.*,split_part(expected_key,':',1) source,split_part(expected_key,':',2)::uuid entity_id
 from scheduled_expected e where not coalesce(completed,false)
 order by e.student_id,case when split_part(expected_key,':',1) in ('regular','class-makeup') then 'class:'||split_part(expected_key,':',2)||':'||occurrence_date else expected_key end,case when kind like '%보강%' then 0 else 1 end,start_time
 ),
 enriched as (
 select e.*,c.id class_id,sp.id session_id,ca.id assignment_id,
 coalesce(case when e.source='special' then sp.ends_at when e.source='correction' then coalesce(cx.target_end_time,ca.end_time) else coalesce((l.ends_at at time zone 'Asia/Seoul')::time,(select max(x.end_time) from public.schedule_exceptions x where x.class_id=c.id and x.replacement_date=e.occurrence_date and x.kind in ('changed','makeup'))) end,
 (select max(sc.end_time) from public.class_schedules sc where sc.class_id=c.id and sc.weekday=extract(isodow from e.occurrence_date) and (e.start_time is null or sc.start_time=e.start_time)),e.start_time+interval '90 minutes','23:59'::time) end_time,
 case when e.source='special' then array[sp.teacher_profile_id]
 when e.source='correction' then array_remove(array[coalesce(ca.tutor_profile_id,ca.teacher_profile_id),ca.supervisor_profile_id],null)||array(select sa.assistant_profile_id from public.correction_slot_assistants sa where sa.weekday=extract(isodow from e.occurrence_date) and sa.start_time=e.start_time)
 else case when l.teacher_profile_id is not null then array[l.teacher_profile_id] else array(select ct.profile_id from public.class_teachers ct where ct.class_id=c.id) end end owner_ids,
 case when e.source='special' then exists(select 1 from public.teacher_special_lesson_students a where a.session_id=sp.id and a.student_id=e.student_id and a.attendance_status is not null)
 when e.source='correction' then exists(select 1 from public.correction_reports r where r.assignment_id=ca.id and r.student_id=e.student_id and r.correction_date=e.occurrence_date and r.start_time=e.start_time and r.attendance_status<>'scheduled')
 else exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=e.student_id and a.status::text in ('present','late','absent','excused')) end has_attendance
 from identified e
 left join public.classes c on e.source in ('regular','class-makeup') and c.id=e.entity_id
 left join lateral(select * from public.lessons ll where ll.class_id=c.id and ll.lesson_date=e.occurrence_date order by ll.starts_at limit 1) l on true
 left join public.teacher_special_lessons sp on e.source='special' and sp.id=e.entity_id
 left join public.correction_assignments ca on e.source='correction' and ca.id=e.entity_id
 left join public.correction_schedule_exceptions cx on cx.assignment_id=ca.id and cx.target_date=e.occurrence_date and cx.target_start_time=e.start_time and cx.kind in ('move','extra')
 where coalesce(l.status,'')<>'cancelled'
 ),
 scoped as (
 select e.*,coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name,p.id) from public.profiles p where p.id=any(e.owner_ids) and p.is_active and p.role in ('admin','sub_admin','teacher','assistant','manager')),'[]'::jsonb) owners
 from enriched e where admin or uid=any(e.owner_ids)
 )
 select coalesce(jsonb_agg(item order by item->>'date',item->>'time',item->>'studentName'),'[]'::jsonb) into result from (
 select distinct jsonb_build_object('key',e.expected_key||':'||s.id,'source',e.source,'kind',e.kind,'title',e.title,'date',e.occurrence_date,'time',to_char(e.start_time,'HH24:MI'),'endTime',to_char(e.end_time,'HH24:MI'),
 'due',((e.occurrence_date+e.end_time) at time zone 'Asia/Seoul')<=now(),
 'studentId',s.id,'studentName',s.name,'classId',e.class_id,'sessionId',e.session_id,'assignmentId',e.assignment_id,'owners',e.owners,
 'reason',case when e.has_attendance then '완료 처리 필요' else '출결 입력 필요' end,
 'requestedAt',(select max(r.requested_at) from public.record_work_requests r where r.recipient_id=uid and r.work_date=e.occurrence_date)) item
 from scoped e join public.students s on s.id=e.student_id
 ) q;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_student_learning_history(p_student_id uuid, p_limit integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  viewer_role public.user_role;
  safe_limit integer;
  result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('admin','teacher','sub_admin') then
    raise exception '교직원 계정만 학생 수업 기록을 확인할 수 있습니다.';
  end if;
  if p_student_id is null then return '[]'::jsonb; end if;
  safe_limit := greatest(1, least(coalesce(p_limit, 300), 500));

  select coalesce(jsonb_agg(report_row order by lesson_date desc, starts_at desc), '[]'::jsonb)
  into result
  from (
    select jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'lessonContent', coalesce(l.lesson_content, ''),
      'homeworkContent', coalesce(nullif(trim(hr.assigned_homework), ''), nullif(trim(l.homework_content), ''), ''),
      'examContent', coalesce(l.exam_content, ''),
      'attendance', case when a.id is null then null else jsonb_build_object(
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'absenceReason', coalesce(a.absence_reason, ''),
        'note', coalesce(a.note, '')
      ) end,
      'homeworkResult', case
        when hr.id is null or (
          nullif(trim(coalesce(hr.status, '')), '') is null
          and nullif(trim(coalesce(hr.note, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_status, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_note, '')), '') is null
        ) then null
        else jsonb_build_object(
          'status', coalesce(nullif(hr.inspection_status, ''), hr.status, ''),
          'note', coalesce(nullif(hr.inspection_note, ''), hr.note, '')
        )
      end,
      'exams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', er.id,
          'examType', coalesce(er.exam_type, ''),
          'examTitle', coalesce(er.exam_title, ''),
          'score', er.score,
          'maxScore', coalesce(er.max_score, 100),
          'percent', case when er.score is null or coalesce(er.max_score, 0) <= 0 then null else round(er.score / er.max_score * 100, 1) end,
          'evaluation', coalesce(er.evaluation, ''),
          'feedback', coalesce(er.feedback, '')
        ) order by er.created_at, er.id)
        from public.lesson_exam_results er
        where er.lesson_id = l.id
          and er.student_id = p_student_id
          and (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) as report_row, l.lesson_date, l.starts_at
    from public.lessons l
    join public.classes c on c.id = l.class_id
    join public.enrollments e on e.class_id = c.id and e.student_id = p_student_id
    left join public.profiles tp on tp.id = l.teacher_profile_id
    left join public.attendance a on a.lesson_id = l.id and a.student_id = p_student_id
    left join public.lesson_homework_results hr on hr.lesson_id = l.id and hr.student_id = p_student_id
    where e.started_on <= l.lesson_date
      and (e.ended_on is null or e.ended_on >= l.lesson_date)
      and l.lesson_date <= current_date
      and (
        a.id is not null
        or nullif(trim(l.lesson_content), '') is not null
        or nullif(trim(l.homework_content), '') is not null
        or nullif(trim(l.exam_content), '') is not null
        or (
          hr.id is not null and (
            nullif(trim(coalesce(hr.status, '')), '') is not null
            or nullif(trim(coalesce(hr.note, '')), '') is not null
            or nullif(trim(coalesce(hr.assigned_homework, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_status, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_note, '')), '') is not null
          )
        )
        or exists (
          select 1 from public.lesson_exam_results er
          where er.lesson_id = l.id
            and er.student_id = p_student_id
            and (
              er.score is not null
              or nullif(trim(coalesce(er.exam_type, '')), '') is not null
              or nullif(trim(coalesce(er.exam_title, '')), '') is not null
              or nullif(trim(coalesce(er.evaluation, '')), '') is not null
              or nullif(trim(coalesce(er.feedback, '')), '') is not null
            )
        )
      )
    order by l.lesson_date desc, l.starts_at desc
    limit safe_limit
  ) reports;
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.can_staff_report_student(p_student_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.current_user_role()='admin' or (
    public.current_user_role() in ('teacher','sub_admin') and (
      exists(select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id where e.student_id=p_student_id and ct.profile_id=auth.uid())
      or exists(select 1 from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.teacher_profile_id=auth.uid())
      or exists(select 1 from public.correction_assignments ca where ca.student_id=p_student_id and ca.teacher_profile_id=auth.uid())
    )
  )
$function$
;

CREATE OR REPLACE FUNCTION public.specialized_learning_history_range(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  viewer_role public.user_role;
  safe_limit integer;
  result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('admin','teacher','sub_admin') then
    raise exception '교직원 계정만 학생 수업 기록을 확인할 수 있습니다.';
  end if;
  if p_student_id is null then return '[]'::jsonb; end if;
  safe_limit := greatest(1, least(500, 500));

  select coalesce(jsonb_agg(report_row order by lesson_date desc, starts_at desc), '[]'::jsonb)
  into result
  from (
    select jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'lessonContent', coalesce(l.lesson_content, ''),
      'homeworkContent', coalesce(nullif(trim(hr.assigned_homework), ''), nullif(trim(l.homework_content), ''), ''),
      'examContent', coalesce(l.exam_content, ''),
      'attendance', case when a.id is null then null else jsonb_build_object(
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'absenceReason', coalesce(a.absence_reason, ''),
        'note', coalesce(a.note, '')
      ) end,
      'homeworkResult', case
        when hr.id is null or (
          nullif(trim(coalesce(hr.status, '')), '') is null
          and nullif(trim(coalesce(hr.note, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_status, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_note, '')), '') is null
        ) then null
        else jsonb_build_object(
          'status', coalesce(nullif(hr.inspection_status, ''), hr.status, ''),
          'note', coalesce(nullif(hr.inspection_note, ''), hr.note, '')
        )
      end,
      'exams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', er.id,
          'examType', coalesce(er.exam_type, ''),
          'examTitle', coalesce(er.exam_title, ''),
          'score', er.score,
          'maxScore', coalesce(er.max_score, 100),
          'percent', case when er.score is null or coalesce(er.max_score, 0) <= 0 then null else round(er.score / er.max_score * 100, 1) end,
          'evaluation', coalesce(er.evaluation, ''),
          'feedback', coalesce(er.feedback, '')
        ) order by er.created_at, er.id)
        from public.lesson_exam_results er
        where er.lesson_id = l.id
          and er.student_id = p_student_id
          and (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) as report_row, l.lesson_date, l.starts_at
    from public.lessons l
    join public.classes c on c.id = l.class_id
    left join public.profiles tp on tp.id = l.teacher_profile_id
    left join public.attendance a on a.lesson_id = l.id and a.student_id = p_student_id
    left join public.lesson_homework_results hr on hr.lesson_id = l.id and hr.student_id = p_student_id
    where (a.id is not null or exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=p_student_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)))
      and l.lesson_date <= current_date
      and l.lesson_date between p_from and p_to
      and (
        a.id is not null
        or nullif(trim(l.lesson_content), '') is not null
        or nullif(trim(l.homework_content), '') is not null
        or nullif(trim(l.exam_content), '') is not null
        or (
          hr.id is not null and (
            nullif(trim(coalesce(hr.status, '')), '') is not null
            or nullif(trim(coalesce(hr.note, '')), '') is not null
            or nullif(trim(coalesce(hr.assigned_homework, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_status, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_note, '')), '') is not null
          )
        )
        or exists (
          select 1 from public.lesson_exam_results er
          where er.lesson_id = l.id
            and er.student_id = p_student_id
            and (
              er.score is not null
              or nullif(trim(coalesce(er.exam_type, '')), '') is not null
              or nullif(trim(coalesce(er.exam_title, '')), '') is not null
              or nullif(trim(coalesce(er.evaluation, '')), '') is not null
              or nullif(trim(coalesce(er.feedback, '')), '') is not null
            )
        )
      )
    order by l.lesson_date desc, l.starts_at desc
    limit safe_limit
  ) reports;
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.specialized_completed_history_range(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; safe_limit integer;
begin
  if not public.is_staff() and not public.can_send_alimtalk() then raise exception '교직원만 학생 수업 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  safe_limit:=greatest(1,least(500,500));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (select item,lesson_date,starts_at from (
    select jsonb_set(jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))),'{source}','"regular"'::jsonb) item,
      l.lesson_date,l.starts_at::text starts_at
    from jsonb_array_elements(coalesce(public.specialized_learning_history_range(p_student_id,p_from,p_to),'[]'::jsonb)) entry(item)
    join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
    left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=p_student_id
    where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
    union all
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when public.internal_special_student_kind(l.id,p_student_id)='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',public.internal_special_student_kind(l.id,p_student_id),'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=p_student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id
    join public.profiles p on p.id=l.teacher_profile_id
    left join public.academy_subjects s on s.id=l.subject_id
    where l.status='completed' and a.attendance_status is not null and l.lesson_date between p_from and p_to
  ) combined order by lesson_date desc,starts_at desc limit safe_limit) limited;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_learning_report_source(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare base_rows jsonb; result jsonb;
begin
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>31 then raise exception '조회 기간을 확인해 주세요.'; end if;
  if not (public.can_staff_report_student(p_student_id) or public.can_send_alimtalk()) then raise exception '담당 학생의 리포트만 만들 수 있습니다.'; end if;
  base_rows:=public.specialized_completed_history_range(p_student_id,p_from,p_to);
  select coalesce(jsonb_agg(item order by report_date,starts_at),'[]'::jsonb) into result from (
    select jsonb_set(entry.item,'{source}',to_jsonb(case
      when entry.item->>'source'='additional' then 'extra'
      when entry.item->>'source' in ('makeup','extra') then entry.item->>'source'
      when exists(select 1 from public.class_makeup_attendees ma where ma.class_id=(entry.item->>'classId')::uuid and ma.student_id=p_student_id and ma.attendance_date=(entry.item->>'lessonDate')::date) then 'makeup'
      else 'regular' end)) item,
      (entry.item->>'lessonDate')::date report_date,entry.item->>'startsAt' starts_at
    from jsonb_array_elements(coalesce(base_rows,'[]'::jsonb)) entry(item)
    where (entry.item->>'lessonDate')::date between p_from and p_to
    union all
    select jsonb_build_object(
      'lessonId',r.id,'lessonDate',to_char(r.correction_date,'YYYY-MM-DD'),
      'startsAt',to_char(r.correction_date,'YYYY-MM-DD')||'T'||r.start_time::text||'+09:00',
      'classId',r.assignment_id,'className','첨삭','subject',r.subject,'source','correction','room',null,
      'teacherName',coalesce(r.recorded_by_name,'담당 선생님'),'lessonContent',coalesce(r.correction_content,''),
      'homeworkContent',coalesce(r.next_preparation,r.homework_instruction,''),'examContent',coalesce(r.exam_range,''),
      'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),
      'attendance',jsonb_build_object('status',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason','','note',coalesce(r.assistant_feedback,'')),
      'homeworkResult',case when r.homework_status is null then null else jsonb_build_object('status',r.homework_status,'note',coalesce(r.homework_note,'')) end,
      'exams',case when r.exam_title is null and r.exam_score is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'id',r.id,
        'examType',case when coalesce(r.exam_range,'') like '[종류]%' then coalesce(nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),''),'첨삭 평가') else '첨삭 평가' end,
        'examTitle',coalesce(r.exam_title,''),'score',r.exam_score,'maxScore',coalesce(r.exam_max_score,100),
        'percent',case when r.exam_score is null or coalesce(r.exam_max_score,0)<=0 then null else round(r.exam_score/r.exam_max_score*100,1) end,
        'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.teacher_instruction,''))) end
    ) item,r.correction_date report_date,r.start_time::text starts_at
    from public.correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
    where r.student_id=p_student_id and r.correction_date between p_from and p_to and r.published
      and (public.can_send_alimtalk() or ca.teacher_profile_id=auth.uid())
  ) rows;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.notify_staff_live_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; entity uuid; cid uuid; d date; k text;
begin
 for r in select distinct x from jsonb_array_elements(case when tg_op='INSERT' then jsonb_build_array(to_jsonb(new)) when tg_op='DELETE' then jsonb_build_array(to_jsonb(old)) else jsonb_build_array(to_jsonb(old),to_jsonb(new)) end) x loop
  cid:=null;d:=null;
  if tg_argv[0]='calendar' then entity:=(r->>'id')::uuid;
  elsif tg_argv[0]='classes' then
    if tg_table_name='student_schedule_assignments' then select class_id into entity from public.class_schedules where id=(r->>'class_schedule_id')::uuid;
    else entity:=coalesce(r->>'class_id',r->>'id')::uuid;end if;cid:=entity;
  else
    if tg_table_name in ('lessons','class_lesson_roster_overrides') then cid:=(r->>'class_id')::uuid;d:=(r->>'lesson_date')::date;
    elsif tg_table_name='class_daily_notices' then cid:=(r->>'class_id')::uuid;d:=(r->>'notice_date')::date;
    else select class_id,lesson_date into cid,d from public.lessons where id=(r->>'lesson_id')::uuid;end if;
    entity:=cid;
  end if;
  if entity is null then continue;end if;
  k:=tg_argv[0]||':'||entity::text||coalesce(':'||d::text,'');
  insert into public.staff_live_signals(key,topic,entity_id,class_id,record_date) values(k,tg_argv[0],entity,cid,d)
  on conflict(key) do update set changed_at=clock_timestamp();
 end loop;return null;
end $function$
;

create or replace function public.current_user_role() returns public.user_role language sql stable as $$select current_setting('test.role')::public.user_role$$;

create or replace function public.is_staff() returns boolean language sql stable as $$select current_setting('test.role') in ('admin','teacher','sub_admin','assistant','manager')$$;