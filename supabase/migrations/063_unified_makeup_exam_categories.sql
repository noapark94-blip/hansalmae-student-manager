-- 시험 카테고리, 필수 결석 사유, 결석 보강 대기 등록을 한 흐름으로 정리합니다.

create table if not exists public.exam_categories (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 40),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists exam_categories_owner_name_key
  on public.exam_categories(owner_profile_id, lower(trim(name)));

alter table public.exam_categories enable row level security;
drop policy if exists "staff_manage_own_exam_categories" on public.exam_categories;
create policy "staff_manage_own_exam_categories" on public.exam_categories for all to authenticated
  using (public.is_staff() and (owner_profile_id=auth.uid() or public.current_user_role()='admin'))
  with check (public.is_staff() and (owner_profile_id=auth.uid() or public.current_user_role()='admin'));
grant select,insert,update,delete on public.exam_categories to authenticated;

create or replace function public.staff_exam_categories()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_defaults text[]:=array['영단어 시험','주간평가','월간평가','모의고사','기타 시험']; v_name text;
begin
  if not public.is_staff() then raise exception '교직원만 시험 카테고리를 관리할 수 있습니다.'; end if;
  foreach v_name in array v_defaults loop
    insert into public.exam_categories(owner_profile_id,name,sort_order)
    values(auth.uid(),v_name,array_position(v_defaults,v_name)) on conflict do nothing;
  end loop;
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'isActive',is_active,'sortOrder',sort_order) order by sort_order,name)
    from public.exam_categories where owner_profile_id=auth.uid()),'[]'::jsonb);
end $$;

create or replace function public.staff_add_exam_category(p_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 시험 카테고리를 추가할 수 있습니다.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '카테고리 이름을 입력해 주세요.'; end if;
  insert into public.exam_categories(owner_profile_id,name,sort_order)
  values(auth.uid(),trim(p_name),coalesce((select max(sort_order)+1 from public.exam_categories where owner_profile_id=auth.uid()),1))
  on conflict(owner_profile_id,(lower(trim(name)))) do update set is_active=true,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.staff_set_exam_category(p_id uuid,p_name text,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 시험 카테고리를 수정할 수 있습니다.'; end if;
  update public.exam_categories set name=trim(p_name),is_active=p_active,updated_at=now()
  where id=p_id and owner_profile_id=auth.uid();
  if not found then raise exception '시험 카테고리를 찾을 수 없습니다.'; end if;
end $$;

create or replace function public.staff_save_class_attendance(
  p_class_id uuid,p_date date,p_student_id uuid,p_status public.attendance_status,
  p_late_minutes integer default null,p_absence_reason text default null,p_note text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v_lesson_id uuid;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not exists(select 1 from public.enrollments e where e.class_id=p_class_id and e.student_id=p_student_id and e.status='active') then raise exception '이 클래스의 수강생이 아닙니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  insert into public.attendance as attendance_record(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(v_lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then trim(p_absence_reason) end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $$;

-- 화면은 학생·날짜별 대표 시험 한 건만 편집합니다. 과거의 추가 시험 기록은 삭제하지 않습니다.
create or replace function public.staff_save_class_exam_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_lesson uuid; v_student jsonb; v_exam jsonb; v_sid uuid; v_id uuid; v_score numeric; v_max numeric;
begin
  v_lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for v_student in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    v_sid:=(v_student->>'studentId')::uuid;
    if not exists(select 1 from public.enrollments e where e.class_id=p_class_id and e.student_id=v_sid and e.status='active') then raise exception '이 클래스의 수강생이 아닌 학생이 포함되어 있습니다.'; end if;
    v_exam:=coalesce(v_student->'exams'->0,'{}'::jsonb);
    v_id:=nullif(v_exam->>'id','')::uuid; v_score:=nullif(v_exam->>'score','')::numeric; v_max:=coalesce(nullif(v_exam->>'maxScore','')::numeric,100);
    if v_max<=0 or (v_score is not null and (v_score<0 or v_score>v_max)) then raise exception '점수와 만점을 확인해 주세요.'; end if;
    if nullif(trim(v_exam->>'examType'),'') is null and nullif(trim(v_exam->>'examTitle'),'') is null and v_score is null and nullif(trim(v_exam->>'evaluation'),'') is null then continue; end if;
    if v_id is null then
      insert into public.lesson_exam_results(lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,created_by)
      values(v_lesson,v_sid,nullif(trim(v_exam->>'examType'),''),nullif(trim(v_exam->>'examTitle'),''),v_score,v_max,nullif(trim(v_exam->>'evaluation'),''),auth.uid());
    else
      update public.lesson_exam_results set exam_type=nullif(trim(v_exam->>'examType'),''),exam_title=nullif(trim(v_exam->>'examTitle'),''),score=v_score,max_score=v_max,evaluation=nullif(trim(v_exam->>'evaluation'),''),updated_at=now()
      where id=v_id and lesson_id=v_lesson and student_id=v_sid;
    end if;
  end loop;
end $$;

revoke all on function public.staff_exam_categories(),public.staff_add_exam_category(text),public.staff_set_exam_category(uuid,text,boolean) from public;
grant execute on function public.staff_exam_categories(),public.staff_add_exam_category(text),public.staff_set_exam_category(uuid,text,boolean) to authenticated;
notify pgrst,'reload schema';
