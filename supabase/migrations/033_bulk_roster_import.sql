-- 관리자 전용 학생·클래스·수강 배정 CSV 일괄 등록을 제공합니다.
create table public.bulk_import_logs (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  file_name text,
  row_count integer not null,
  students_created integer not null default 0,
  classes_created integer not null default 0,
  enrollments_created integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.bulk_import_logs enable row level security;
create policy "admin_read_bulk_import_logs" on public.bulk_import_logs
  for select to authenticated using (public.current_user_role()='admin');
revoke all on public.bulk_import_logs from anon, authenticated;
grant select on public.bulk_import_logs to authenticated;

create or replace function public.admin_bulk_import_roster(p_rows jsonb,p_file_name text default null)
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare
  item jsonb;
  row_number integer:=0;
  student_name text;
  school_name text;
  grade_name text;
  phone_number text;
  student_status text;
  class_name text;
  subject_name text;
  room_name text;
  fee integer;
  v_student_id uuid;
  v_class_id uuid;
  student_created integer:=0;
  class_created integer:=0;
  enrollment_created integer:=0;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 일괄 등록할 수 있습니다.'; end if;
  if jsonb_typeof(p_rows)<>'array' then raise exception 'CSV 행 형식이 올바르지 않습니다.'; end if;
  if jsonb_array_length(p_rows)=0 or jsonb_array_length(p_rows)>1000 then raise exception '한 번에 1~1000행까지 등록할 수 있습니다.'; end if;

  for item in select value from jsonb_array_elements(p_rows) loop
    row_number:=row_number+1;
    student_name:=nullif(trim(item->>'studentName'),'');
    school_name:=nullif(trim(item->>'school'),'');
    grade_name:=nullif(trim(item->>'grade'),'');
    phone_number:=nullif(regexp_replace(coalesce(item->>'phone',''),'[^0-9]','','g'),'');
    student_status:=lower(coalesce(nullif(trim(item->>'status'),''),'active'));
    class_name:=nullif(trim(item->>'className'),'');
    subject_name:=nullif(trim(item->>'subject'),'');
    room_name:=nullif(trim(item->>'room'),'');
    begin fee:=nullif(regexp_replace(coalesce(item->>'monthlyFee',''),'[^0-9]','','g'),'')::integer;
    exception when invalid_text_representation or numeric_value_out_of_range then raise exception '%행의 월수강료를 확인해 주세요.',row_number; end;

    if student_name is null then raise exception '%행의 학생 이름이 비어 있습니다.',row_number; end if;
    student_status:=case student_status when '재원' then 'active' when '휴원' then 'paused' when '퇴원' then 'completed' else student_status end;
    if student_status not in ('active','paused','completed') then raise exception '%행의 상태를 확인해 주세요.',row_number; end if;
    if class_name is not null and subject_name is null then raise exception '%행은 클래스 과목이 필요합니다.',row_number; end if;

    v_student_id:=null;
    if phone_number is not null then
      select s.id into v_student_id from public.students s where s.name=student_name and regexp_replace(coalesce(s.phone,''),'[^0-9]','','g')=phone_number order by s.created_at limit 1;
    else
      select s.id into v_student_id from public.students s where s.name=student_name and coalesce(s.school,'')=coalesce(school_name,'') and coalesce(s.grade,'')=coalesce(grade_name,'') order by s.created_at limit 1;
    end if;
    if v_student_id is null then
      insert into public.students(name,school,grade,phone,status) values(student_name,school_name,grade_name,phone_number,student_status) returning id into v_student_id;
      student_created:=student_created+1;
    end if;

    if class_name is not null then
      v_class_id:=null;
      select c.id into v_class_id from public.classes c where lower(c.name)=lower(class_name) order by c.created_at limit 1;
      if v_class_id is null then
        insert into public.classes(name,subject,room) values(class_name,subject_name,room_name) returning id into v_class_id;
        class_created:=class_created+1;
      end if;
      if not exists(select 1 from public.enrollments e where e.student_id=v_student_id and e.class_id=v_class_id and e.status='active') then
        insert into public.enrollments(student_id,class_id,status,monthly_fee) values(v_student_id,v_class_id,'active',fee);
        enrollment_created:=enrollment_created+1;
      elsif fee is not null then
        update public.enrollments set monthly_fee=fee where id=(select e.id from public.enrollments e where e.student_id=v_student_id and e.class_id=v_class_id and e.status='active' order by e.started_on desc limit 1);
      end if;
    end if;
  end loop;

  insert into public.bulk_import_logs(requested_by,file_name,row_count,students_created,classes_created,enrollments_created)
  values(auth.uid(),nullif(trim(p_file_name),''),row_number,student_created,class_created,enrollment_created);
  return jsonb_build_object('rows',row_number,'studentsCreated',student_created,'classesCreated',class_created,'enrollmentsCreated',enrollment_created);
end $$;

revoke all on function public.admin_bulk_import_roster(jsonb,text) from public;
grant execute on function public.admin_bulk_import_roster(jsonb,text) to authenticated;
