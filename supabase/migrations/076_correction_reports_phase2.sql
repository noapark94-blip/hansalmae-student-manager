-- 한살매 첨삭 관리 2차: 담당교사 사전 지시 -> 조교 첨삭 기록 -> 가족 리포트/확인

create table if not exists public.correction_reports (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.correction_assignments(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  correction_date date not null,
  subject text not null check(subject in ('국어','영어','수학')),
  attendance_status text not null default 'present' check(attendance_status in ('present','late','absent','excused')),
  late_minutes integer,
  teacher_instruction text,
  exam_title text,
  exam_range text,
  exam_score numeric,
  exam_max_score numeric,
  homework_instruction text,
  homework_status text check(homework_status is null or homework_status in ('complete','partial','missing','excused')),
  homework_note text,
  correction_content text,
  assistant_feedback text,
  next_preparation text,
  recorded_by uuid references public.profiles(id) on delete set null,
  recorded_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(assignment_id,correction_date)
);

create table if not exists public.correction_report_reads(
  report_id uuid not null references public.correction_reports(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key(report_id,viewer_profile_id)
);

alter table public.correction_reports enable row level security;
alter table public.correction_report_reads enable row level security;
create policy correction_reports_staff on public.correction_reports for all to authenticated using(public.is_staff()) with check(public.is_staff());
create policy correction_reads_own on public.correction_report_reads for select to authenticated using(viewer_profile_id=auth.uid());
create policy correction_reads_insert_own on public.correction_report_reads for insert to authenticated with check(viewer_profile_id=auth.uid());
grant select,insert,update,delete on public.correction_reports to authenticated;
grant select,insert,update on public.correction_report_reads to authenticated;

create or replace function public.staff_save_correction_report(
 p_assignment_id uuid,p_correction_date date,p_attendance_status text,p_late_minutes integer,p_teacher_instruction text,
 p_exam_title text,p_exam_range text,p_exam_score numeric,p_exam_max_score numeric,p_homework_instruction text,p_homework_status text,
 p_homework_note text,p_correction_content text,p_assistant_feedback text,p_next_preparation text
) returns uuid language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments; rid uuid; pname text;
begin
 if not public.is_staff() then raise exception '교직원만 첨삭 기록을 저장할 수 있습니다.'; end if;
 select * into a from public.correction_assignments where id=p_assignment_id and active;
 if a.id is null then raise exception '첨삭 배정을 찾을 수 없습니다.'; end if;
 select display_name into pname from public.profiles where id=auth.uid();
 insert into public.correction_reports(assignment_id,student_id,correction_date,subject,attendance_status,late_minutes,teacher_instruction,exam_title,exam_range,exam_score,exam_max_score,homework_instruction,homework_status,homework_note,correction_content,assistant_feedback,next_preparation,recorded_by,recorded_by_name)
 values(a.id,a.student_id,p_correction_date,a.subject,coalesce(p_attendance_status,'present'),p_late_minutes,nullif(trim(p_teacher_instruction),''),nullif(trim(p_exam_title),''),nullif(trim(p_exam_range),''),p_exam_score,p_exam_max_score,nullif(trim(p_homework_instruction),''),p_homework_status,nullif(trim(p_homework_note),''),nullif(trim(p_correction_content),''),nullif(trim(p_assistant_feedback),''),nullif(trim(p_next_preparation),''),auth.uid(),pname)
 on conflict(assignment_id,correction_date) do update set attendance_status=excluded.attendance_status,late_minutes=excluded.late_minutes,teacher_instruction=excluded.teacher_instruction,exam_title=excluded.exam_title,exam_range=excluded.exam_range,exam_score=excluded.exam_score,exam_max_score=excluded.exam_max_score,homework_instruction=excluded.homework_instruction,homework_status=excluded.homework_status,homework_note=excluded.homework_note,correction_content=excluded.correction_content,assistant_feedback=excluded.assistant_feedback,next_preparation=excluded.next_preparation,recorded_by=auth.uid(),recorded_by_name=pname,updated_at=now()
 returning id into rid;
 return rid;
end $$;

create or replace function public.staff_correction_report(p_assignment_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
 return coalesce((select to_jsonb(r) from (select id,"attendance_status" as "attendanceStatus","late_minutes" as "lateMinutes","teacher_instruction" as "teacherInstruction","exam_title" as "examTitle","exam_range" as "examRange","exam_score" as "examScore","exam_max_score" as "examMaxScore","homework_instruction" as "homeworkInstruction","homework_status" as "homeworkStatus","homework_note" as "homeworkNote","correction_content" as "correctionContent","assistant_feedback" as "assistantFeedback","next_preparation" as "nextPreparation","recorded_by_name" as "recordedByName" from public.correction_reports where assignment_id=p_assignment_id and correction_date=p_date) r),'{}'::jsonb);
end $$;

create or replace function public.family_correction_reports(p_student_id uuid,p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.can_access_student(p_student_id) then raise exception '학생 정보 접근 권한이 없습니다.'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q."correctionDate" desc) from (select r.id,r.correction_date as "correctionDate",r.subject,r.attendance_status as "attendanceStatus",r.late_minutes as "lateMinutes",r.exam_title as "examTitle",r.exam_range as "examRange",r.exam_score as "examScore",r.exam_max_score as "examMaxScore",r.homework_instruction as "homeworkInstruction",r.homework_status as "homeworkStatus",r.homework_note as "homeworkNote",r.correction_content as "correctionContent",r.assistant_feedback as "assistantFeedback",r.next_preparation as "nextPreparation",r.recorded_by_name as "recordedByName" from public.correction_reports r where r.student_id=p_student_id and (r.correction_content is not null or r.exam_title is not null or r.homework_status is not null or r.assistant_feedback is not null) order by r.correction_date desc,r.updated_at desc limit greatest(1,least(coalesce(p_limit,20),50))) q),'[]'::jsonb);
end $$;

create or replace function public.family_correction_report_reads(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$;
begin
 if not public.can_access_student(p_student_id) then raise exception '학생 정보 접근 권한이 없습니다.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('reportId',x.report_id,'viewedAt',x.viewed_at)) from public.correction_report_reads x where x.student_id=p_student_id and x.viewer_profile_id=auth.uid()),'[]'::jsonb);
end $$;

create or replace function public.mark_family_correction_report_read(p_student_id uuid,p_report_id uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare ts timestamptz:=now();
begin
 if not public.can_access_student(p_student_id) then raise exception '학생 정보 접근 권한이 없습니다.'; end if;
 if not exists(select 1 from public.correction_reports where id=p_report_id and student_id=p_student_id) then raise exception '첨삭 리포트를 찾을 수 없습니다.'; end if;
 insert into public.correction_report_reads(report_id,student_id,viewer_profile_id,viewed_at) values(p_report_id,p_student_id,auth.uid(),ts) on conflict(report_id,viewer_profile_id) do update set viewed_at=excluded.viewed_at;
 return ts;
end $$;

revoke all on function public.staff_save_correction_report(uuid,date,text,integer,text,text,text,numeric,numeric,text,text,text,text,text,text),public.staff_correction_report(uuid,date),public.family_correction_reports(uuid,integer),public.family_correction_report_reads(uuid),public.mark_family_correction_report_read(uuid,uuid) from public;
grant execute on function public.staff_save_correction_report(uuid,date,text,integer,text,text,text,numeric,numeric,text,text,text,text,text,text),public.staff_correction_report(uuid,date),public.family_correction_reports(uuid,integer),public.family_correction_report_reads(uuid),public.mark_family_correction_report_read(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
