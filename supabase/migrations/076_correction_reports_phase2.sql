-- 한살매 첨삭 관리 2차: 담당교사 사전 지시 -> 조교 기록 -> 가족 리포트/확인

create table if not exists public.correction_reports (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.correction_assignments(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  correction_date date not null,
  start_time time not null,
  end_time time not null,
  subject text not null check(subject in ('국어','영어','수학')),
  attendance_status text not null default 'scheduled' check(attendance_status in ('scheduled','present','late','absent')),
  late_minutes integer check(late_minutes is null or late_minutes>=0),
  teacher_instruction text,
  exam_title text,
  exam_range text,
  exam_score numeric,
  exam_max_score numeric,
  evaluation text,
  homework_instruction text,
  homework_status text check(homework_status is null or homework_status in ('complete','partial','missing','not_checked')),
  homework_note text,
  correction_content text,
  assistant_feedback text,
  next_preparation text,
  published boolean not null default false,
  instruction_by uuid references public.profiles(id) on delete set null,
  recorded_by uuid references public.profiles(id) on delete set null,
  recorded_by_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(assignment_id,correction_date,start_time)
);

create index if not exists correction_reports_student_date_idx on public.correction_reports(student_id,correction_date desc);

create table if not exists public.correction_report_reads(
  report_id uuid not null references public.correction_reports(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key(report_id,viewer_profile_id)
);

alter table public.correction_reports enable row level security;
alter table public.correction_report_reads enable row level security;
drop policy if exists correction_reports_staff on public.correction_reports;
create policy correction_reports_staff on public.correction_reports for all to authenticated using(public.is_staff()) with check(public.is_staff());
drop policy if exists correction_reads_own on public.correction_report_reads;
create policy correction_reads_own on public.correction_report_reads for select to authenticated using(viewer_profile_id=auth.uid());
grant select,insert,update,delete on public.correction_reports to authenticated;
grant select on public.correction_report_reads to authenticated;

create or replace function public.staff_save_correction_report(
 p_assignment_id uuid,p_correction_date date,p_start_time time,p_end_time time,p_attendance_status text,p_late_minutes integer,p_teacher_instruction text,
 p_exam_title text,p_exam_range text,p_exam_score numeric,p_exam_max_score numeric,p_evaluation text,p_homework_instruction text,p_homework_status text,
 p_homework_note text,p_correction_content text,p_assistant_feedback text,p_next_preparation text,p_published boolean
) returns uuid language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments; rid uuid; pname text;
begin
 if not public.is_staff() then raise exception '교직원만 첨삭 기록을 저장할 수 있습니다.'; end if;
 select * into a from public.correction_assignments where id=p_assignment_id and active;
 if a.id is null then raise exception '첨삭 배정을 찾을 수 없습니다.'; end if;
 if p_start_time>=p_end_time then raise exception '첨삭 시간을 확인해 주세요.'; end if;
 if p_attendance_status not in ('scheduled','present','late','absent') then raise exception '출석 상태를 확인해 주세요.'; end if;
 select display_name into pname from public.profiles where id=auth.uid();
 insert into public.correction_reports(assignment_id,student_id,correction_date,start_time,end_time,subject,attendance_status,late_minutes,teacher_instruction,exam_title,exam_range,exam_score,exam_max_score,evaluation,homework_instruction,homework_status,homework_note,correction_content,assistant_feedback,next_preparation,published,instruction_by,recorded_by,recorded_by_name)
 values(a.id,a.student_id,p_correction_date,p_start_time,p_end_time,a.subject,coalesce(p_attendance_status,'scheduled'),case when p_attendance_status='late' then p_late_minutes else null end,nullif(trim(p_teacher_instruction),''),nullif(trim(p_exam_title),''),nullif(trim(p_exam_range),''),p_exam_score,p_exam_max_score,nullif(trim(p_evaluation),''),nullif(trim(p_homework_instruction),''),nullif(p_homework_status,''),nullif(trim(p_homework_note),''),nullif(trim(p_correction_content),''),nullif(trim(p_assistant_feedback),''),nullif(trim(p_next_preparation),''),coalesce(p_published,false),case when nullif(trim(p_teacher_instruction),'') is null then null else auth.uid() end,auth.uid(),pname)
 on conflict(assignment_id,correction_date,start_time) do update set end_time=excluded.end_time,attendance_status=excluded.attendance_status,late_minutes=excluded.late_minutes,teacher_instruction=excluded.teacher_instruction,exam_title=excluded.exam_title,exam_range=excluded.exam_range,exam_score=excluded.exam_score,exam_max_score=excluded.exam_max_score,evaluation=excluded.evaluation,homework_instruction=excluded.homework_instruction,homework_status=excluded.homework_status,homework_note=excluded.homework_note,correction_content=excluded.correction_content,assistant_feedback=excluded.assistant_feedback,next_preparation=excluded.next_preparation,published=excluded.published,instruction_by=case when excluded.teacher_instruction is distinct from public.correction_reports.teacher_instruction then auth.uid() else public.correction_reports.instruction_by end,recorded_by=auth.uid(),recorded_by_name=pname,updated_at=now()
 returning id into rid;
 return rid;
end $$;

create or replace function public.staff_correction_report(p_assignment_id uuid,p_date date,p_start_time time)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
 return coalesce((select jsonb_build_object('id',r.id,'attendanceStatus',r.attendance_status,'lateMinutes',r.late_minutes,'teacherInstruction',coalesce(r.teacher_instruction,''),'examTitle',coalesce(r.exam_title,''),'examRange',coalesce(r.exam_range,''),'examScore',r.exam_score,'examMaxScore',r.exam_max_score,'evaluation',coalesce(r.evaluation,''),'homeworkInstruction',coalesce(r.homework_instruction,''),'homeworkStatus',r.homework_status,'homeworkNote',coalesce(r.homework_note,''),'correctionContent',coalesce(r.correction_content,''),'assistantFeedback',coalesce(r.assistant_feedback,''),'nextPreparation',coalesce(r.next_preparation,''),'published',r.published,'recordedByName',r.recorded_by_name) from public.correction_reports r where r.assignment_id=p_assignment_id and r.correction_date=p_date and r.start_time=p_start_time),'{}'::jsonb);
end $$;

create or replace function public.family_correction_reports(p_student_id uuid,p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role; allowed_id uuid;
begin
 role_now:=public.current_user_role();
 if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
 elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
 if allowed_id is null then raise exception '연결된 학생의 첨삭 리포트만 확인할 수 있습니다.'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q."correctionDate" desc,q."startTime" desc) from (select r.id,r.correction_date as "correctionDate",r.start_time as "startTime",r.end_time as "endTime",r.subject,r.attendance_status as "attendanceStatus",r.late_minutes as "lateMinutes",r.exam_title as "examTitle",r.exam_range as "examRange",r.exam_score as "examScore",r.exam_max_score as "examMaxScore",r.evaluation,r.homework_instruction as "homeworkInstruction",r.homework_status as "homeworkStatus",r.homework_note as "homeworkNote",r.correction_content as "correctionContent",r.assistant_feedback as "assistantFeedback",r.next_preparation as "nextPreparation",r.recorded_by_name as "recordedByName" from public.correction_reports r where r.student_id=allowed_id and r.published order by r.correction_date desc,r.start_time desc limit greatest(1,least(coalesce(p_limit,20),50))) q),'[]'::jsonb);
end $$;

create or replace function public.family_correction_report_reads(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role; allowed_id uuid;
begin
 role_now:=public.current_user_role();
 if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
 elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
 if allowed_id is null then raise exception '연결된 학생의 첨삭 확인 상태만 볼 수 있습니다.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('reportId',x.report_id,'viewedAt',x.viewed_at) order by x.viewed_at desc) from public.correction_report_reads x where x.student_id=allowed_id and x.viewer_profile_id=auth.uid()),'[]'::jsonb);
end $$;

create or replace function public.mark_family_correction_report_read(p_student_id uuid,p_report_id uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare role_now public.user_role; allowed_id uuid; ts timestamptz:=now();
begin
 role_now:=public.current_user_role();
 if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
 elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
 if allowed_id is null or not exists(select 1 from public.correction_reports where id=p_report_id and student_id=allowed_id and published) then raise exception '확인할 수 없는 첨삭 리포트입니다.'; end if;
 insert into public.correction_report_reads(report_id,student_id,viewer_profile_id,viewed_at) values(p_report_id,allowed_id,auth.uid(),ts) on conflict(report_id,viewer_profile_id) do update set viewed_at=excluded.viewed_at;
 return ts;
end $$;

-- staff_save_correction_report 실제 인자는 19개입니다.
revoke all on function public.staff_save_correction_report(uuid,date,time,time,text,integer,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean),public.staff_correction_report(uuid,date,time),public.family_correction_reports(uuid,integer),public.family_correction_report_reads(uuid),public.mark_family_correction_report_read(uuid,uuid) from public;
grant execute on function public.staff_save_correction_report(uuid,date,time,time,text,integer,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean),public.staff_correction_report(uuid,date,time),public.family_correction_reports(uuid,integer),public.family_correction_report_reads(uuid),public.mark_family_correction_report_read(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
