create table if not exists public.academic_calendar_events (
  id uuid primary key default gen_random_uuid(),
  school text not null,
  grade text,
  category text not null check(category in ('exam','vacation','admission','mock','school','intensive','other')),
  title text not null,
  starts_on date not null,
  ends_on date not null,
  starts_at time,
  ends_at time,
  class_id uuid references public.classes(id) on delete set null,
  teacher_profile_id uuid references public.profiles(id) on delete set null,
  note text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(ends_on>=starts_on),
  check((starts_at is null and ends_at is null) or (starts_at is not null and ends_at is not null and ends_at>starts_at))
);
create index if not exists academic_calendar_events_date_idx on public.academic_calendar_events(starts_on,ends_on);
create index if not exists academic_calendar_events_school_idx on public.academic_calendar_events(school);
alter table public.academic_calendar_events enable row level security;
grant select,insert,update,delete on public.academic_calendar_events to authenticated;

create or replace function public.staff_academic_calendar_board(p_year integer)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '학사일정 조회 권한이 없습니다.'; end if;
 return jsonb_build_object(
  'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'school',e.school,'grade',e.grade,'category',e.category,'title',e.title,'startsOn',e.starts_on,'endsOn',e.ends_on,'startsAt',e.starts_at,'endsAt',e.ends_at,'classId',e.class_id,'className',c.name,'teacherId',e.teacher_profile_id,'teacherName',tp.display_name,'note',e.note,'createdBy',e.created_by,'authorName',author.display_name,'canEdit',(e.created_by=auth.uid() or public.current_user_role()='admin')) order by e.starts_on,e.title) from public.academic_calendar_events e left join public.classes c on c.id=e.class_id left join public.profiles tp on tp.id=e.teacher_profile_id join public.profiles author on author.id=e.created_by where e.starts_on<=make_date(p_year,12,31) and e.ends_on>=make_date(p_year,1,1)),'[]'::jsonb),
  'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct trim(s.school) school from public.students s where nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'school',null,'subject',coalesce(sub.name,c.subject),'teacherIds',coalesce((select jsonb_agg(ct.profile_id) from public.class_teachers ct where ct.class_id=c.id),'[]'::jsonb)) order by c.name) from public.classes c left join public.academy_subjects sub on sub.id=c.subject_id where c.active and (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))),'[]'::jsonb),
  'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','manager') and (public.current_user_role()='admin' or p.id=auth.uid())),'[]'::jsonb)
 );
end $$;

create or replace function public.staff_save_academic_calendar_event(p_id uuid,p_school text,p_grade text,p_category text,p_title text,p_starts_on date,p_ends_on date,p_starts_at time,p_ends_at time,p_class_id uuid,p_teacher_id uuid,p_note text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_role public.user_role:=public.current_user_role();
begin
 if not public.is_staff() or v_role='assistant' then raise exception '학사일정 저장 권한이 없습니다.'; end if;
 if p_category not in ('exam','vacation','admission','mock','school','intensive','other') then raise exception '일정 종류를 확인해 주세요.'; end if;
 if nullif(trim(p_school),'') is null or nullif(trim(p_title),'') is null then raise exception '학교와 일정명을 입력해 주세요.'; end if;
 if p_ends_on<p_starts_on then raise exception '종료일을 확인해 주세요.'; end if;
 if (p_starts_at is null)<>(p_ends_at is null) or (p_starts_at is not null and p_ends_at<=p_starts_at) then raise exception '일정 시간을 확인해 주세요.'; end if;
 if p_class_id is not null and v_role<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then raise exception '담당 클래스만 연결할 수 있습니다.'; end if;
 if p_teacher_id is not null and v_role<>'admin' and p_teacher_id<>auth.uid() then raise exception '본인 일정만 등록할 수 있습니다.'; end if;
 if p_id is null then
  insert into public.academic_calendar_events(school,grade,category,title,starts_on,ends_on,starts_at,ends_at,class_id,teacher_profile_id,note,created_by) values(trim(p_school),nullif(trim(p_grade),''),p_category,trim(p_title),p_starts_on,p_ends_on,p_starts_at,p_ends_at,p_class_id,coalesce(p_teacher_id,auth.uid()),nullif(trim(p_note),''),auth.uid()) returning id into v_id;
 else
  update public.academic_calendar_events set school=trim(p_school),grade=nullif(trim(p_grade),''),category=p_category,title=trim(p_title),starts_on=p_starts_on,ends_on=p_ends_on,starts_at=p_starts_at,ends_at=p_ends_at,class_id=p_class_id,teacher_profile_id=coalesce(p_teacher_id,auth.uid()),note=nullif(trim(p_note),''),updated_at=now() where id=p_id and (created_by=auth.uid() or v_role='admin') returning id into v_id;
  if v_id is null then raise exception '수정 권한이 없습니다.'; end if;
 end if;
 return v_id;
end $$;

create or replace function public.staff_delete_academic_calendar_event(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '삭제 권한이 없습니다.'; end if;
 delete from public.academic_calendar_events where id=p_id and (created_by=auth.uid() or public.current_user_role()='admin');
 if not found then raise exception '삭제 권한이 없습니다.'; end if;
end $$;
revoke all on function public.staff_academic_calendar_board(integer),public.staff_save_academic_calendar_event(uuid,text,text,text,text,date,date,time,time,uuid,uuid,text),public.staff_delete_academic_calendar_event(uuid) from public,anon;
grant execute on function public.staff_academic_calendar_board(integer),public.staff_save_academic_calendar_event(uuid,text,text,text,text,date,date,time,time,uuid,uuid,text),public.staff_delete_academic_calendar_event(uuid) to authenticated;
notify pgrst,'reload schema';
