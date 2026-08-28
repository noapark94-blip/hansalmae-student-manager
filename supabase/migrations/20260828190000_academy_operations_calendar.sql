alter table public.academic_calendar_events
  add column if not exists event_scope text not null default 'school',
  add column if not exists contact_name text,
  add column if not exists contact_phone text,
  add column if not exists location text,
  add column if not exists status text not null default 'scheduled';

alter table public.academic_calendar_events alter column school drop not null;
alter table public.academic_calendar_events drop constraint if exists academic_calendar_events_category_check;
alter table public.academic_calendar_events drop constraint if exists academic_calendar_events_event_scope_check;
alter table public.academic_calendar_events drop constraint if exists academic_calendar_events_status_check;
alter table public.academic_calendar_events
  add constraint academic_calendar_events_event_scope_check check(event_scope in ('school','academy')),
  add constraint academic_calendar_events_category_check check(category in (
    'exam','vacation','admission','mock','school','intensive','other',
    'consultation','trial','placement','academy_event','closure'
  )),
  add constraint academic_calendar_events_status_check check(status in ('scheduled','completed','enrolled','cancelled','no_show'));

create index if not exists academic_calendar_events_scope_date_idx
  on public.academic_calendar_events(event_scope,starts_on,ends_on);

create or replace function public.staff_academic_calendar_board(p_year integer)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '일정 조회 권한이 없습니다.'; end if;
 return jsonb_build_object(
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'scope',e.event_scope,'school',e.school,'grade',e.grade,
      'category',e.category,'title',e.title,'startsOn',e.starts_on,'endsOn',e.ends_on,
      'startsAt',e.starts_at,'endsAt',e.ends_at,'classId',e.class_id,'className',c.name,
      'teacherId',e.teacher_profile_id,'teacherName',tp.display_name,'note',e.note,
      'contactName',e.contact_name,'contactPhone',e.contact_phone,'location',e.location,
      'status',e.status,'createdBy',e.created_by,'authorName',author.display_name,
      'canEdit',(e.created_by=auth.uid() or public.current_user_role()='admin')
    ) order by e.starts_on,e.starts_at nulls last,e.title)
    from public.academic_calendar_events e
    left join public.classes c on c.id=e.class_id
    left join public.profiles tp on tp.id=e.teacher_profile_id
    join public.profiles author on author.id=e.created_by
    where e.starts_on<=make_date(p_year,12,31) and e.ends_on>=make_date(p_year,1,1)
  ),'[]'::jsonb),
  'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct trim(s.school) school from public.students s where nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'school',null,'subject',coalesce(sub.name,c.subject),'teacherIds',coalesce((select jsonb_agg(ct.profile_id) from public.class_teachers ct where ct.class_id=c.id),'[]'::jsonb)) order by c.name) from public.classes c left join public.academy_subjects sub on sub.id=c.subject_id where c.active and (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))),'[]'::jsonb),
  'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','manager') and (public.current_user_role()='admin' or p.id=auth.uid())),'[]'::jsonb)
 );
end $$;

create or replace function public.staff_save_calendar_event(
 p_id uuid,p_scope text,p_school text,p_grade text,p_category text,p_title text,
 p_starts_on date,p_ends_on date,p_starts_at time,p_ends_at time,p_class_id uuid,
 p_teacher_id uuid,p_note text,p_contact_name text,p_contact_phone text,
 p_location text,p_status text
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_role public.user_role:=public.current_user_role();
begin
 if not public.is_staff() or v_role='assistant' then raise exception '일정 저장 권한이 없습니다.'; end if;
 if p_scope not in ('school','academy') then raise exception '일정 구분을 확인해 주세요.'; end if;
 if p_scope='school' and p_category not in ('exam','vacation','admission','mock','school','intensive','other') then raise exception '학교 일정 종류를 확인해 주세요.'; end if;
 if p_scope='academy' and p_category not in ('consultation','trial','placement','academy_event','closure','other') then raise exception '학원 일정 종류를 확인해 주세요.'; end if;
 if nullif(trim(p_title),'') is null then raise exception '일정명을 입력해 주세요.'; end if;
 if p_scope='school' and nullif(trim(p_school),'') is null then raise exception '학교를 입력해 주세요.'; end if;
 if p_status not in ('scheduled','completed','enrolled','cancelled','no_show') then raise exception '진행 상태를 확인해 주세요.'; end if;
 if p_ends_on<p_starts_on then raise exception '종료일을 확인해 주세요.'; end if;
 if (p_starts_at is null)<>(p_ends_at is null) or (p_starts_at is not null and p_ends_at<=p_starts_at) then raise exception '일정 시간을 확인해 주세요.'; end if;
 if p_class_id is not null and v_role<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then raise exception '담당 클래스만 연결할 수 있습니다.'; end if;
 if p_teacher_id is not null and v_role<>'admin' and p_teacher_id<>auth.uid() then raise exception '본인 일정만 등록할 수 있습니다.'; end if;
 if p_id is null then
  insert into public.academic_calendar_events(
   event_scope,school,grade,category,title,starts_on,ends_on,starts_at,ends_at,
   class_id,teacher_profile_id,note,contact_name,contact_phone,location,status,created_by
  ) values(
   p_scope,nullif(trim(p_school),''),nullif(trim(p_grade),''),p_category,trim(p_title),
   p_starts_on,p_ends_on,p_starts_at,p_ends_at,p_class_id,coalesce(p_teacher_id,auth.uid()),
   nullif(trim(p_note),''),nullif(trim(p_contact_name),''),nullif(trim(p_contact_phone),''),
   nullif(trim(p_location),''),p_status,auth.uid()
  ) returning id into v_id;
 else
  update public.academic_calendar_events set
   event_scope=p_scope,school=nullif(trim(p_school),''),grade=nullif(trim(p_grade),''),
   category=p_category,title=trim(p_title),starts_on=p_starts_on,ends_on=p_ends_on,
   starts_at=p_starts_at,ends_at=p_ends_at,class_id=p_class_id,
   teacher_profile_id=coalesce(p_teacher_id,auth.uid()),note=nullif(trim(p_note),''),
   contact_name=nullif(trim(p_contact_name),''),contact_phone=nullif(trim(p_contact_phone),''),
   location=nullif(trim(p_location),''),status=p_status,updated_at=now()
  where id=p_id and (created_by=auth.uid() or v_role='admin') returning id into v_id;
  if v_id is null then raise exception '수정 권한이 없습니다.'; end if;
 end if;
 return v_id;
end $$;

revoke all on function public.staff_save_calendar_event(uuid,text,text,text,text,text,date,date,time,time,uuid,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.staff_save_calendar_event(uuid,text,text,text,text,text,date,date,time,time,uuid,uuid,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
