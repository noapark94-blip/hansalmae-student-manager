-- 학교·학원 일정 종류를 관리자가 안전하게 관리할 수 있게 합니다.

create table public.academic_calendar_categories (
  id text primary key,
  scope text not null check (scope in ('school','academy')),
  label text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint academic_calendar_categories_label_length check (char_length(trim(label)) between 1 and 30),
  constraint academic_calendar_categories_scope_label_unique unique (scope,label)
);

insert into public.academic_calendar_categories(id,scope,label,sort_order) values
 ('exam','school','중간·기말고사',10),('mock','school','모의고사·수능',20),
 ('admission','school','원서접수·입시',30),('vacation','school','개학·방학',40),
 ('school','school','학교 행사',50),('intensive','school','시험 직전 보강',60),
 ('other','school','기타',70),
 ('consultation','academy','상담 예약',10),('trial','academy','청강·체험',20),
 ('placement','academy','레벨테스트',30),('academy_event','academy','특강·행사',40),
 ('closure','academy','휴무·운영 변경',50),('other_academy','academy','기타',60)
on conflict do nothing;

alter table public.academic_calendar_events
  drop constraint if exists academic_calendar_events_category_check;

-- 기존 학원 일정의 other는 학교용 other와 키가 겹치므로 별도 키로 옮깁니다.
update public.academic_calendar_events
set category='other_academy'
where event_scope='academy' and category='other';

alter table public.academic_calendar_categories enable row level security;
revoke all on table public.academic_calendar_categories from public,anon,authenticated;

create index academic_calendar_categories_scope_order_idx
  on public.academic_calendar_categories(scope,is_active desc,sort_order,label);

create or replace function public.staff_academic_calendar_board(p_year integer)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '일정 조회 권한이 없습니다.'; end if;
 return jsonb_build_object(
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'scope',e.event_scope,'school',e.school,'grade',e.grade,
      'category',e.category,'categoryLabel',coalesce(cat.label,'기타'),'title',e.title,
      'startsOn',e.starts_on,'endsOn',e.ends_on,'startsAt',e.starts_at,'endsAt',e.ends_at,
      'classId',e.class_id,'className',c.name,'teacherId',e.teacher_profile_id,
      'teacherName',tp.display_name,'note',e.note,'contactName',e.contact_name,
      'contactPhone',e.contact_phone,'location',e.location,'status',e.status,
      'createdBy',e.created_by,'authorName',author.display_name,
      'canEdit',(e.created_by=auth.uid() or public.current_user_role()='admin')
    ) order by e.starts_on,e.starts_at nulls last,e.title)
    from public.academic_calendar_events e
    left join public.academic_calendar_categories cat on cat.id=e.category and cat.scope=e.event_scope
    left join public.classes c on c.id=e.class_id
    left join public.profiles tp on tp.id=e.teacher_profile_id
    join public.profiles author on author.id=e.created_by
    where e.starts_on<=make_date(p_year,12,31) and e.ends_on>=make_date(p_year,1,1)
  ),'[]'::jsonb),
  'categories',coalesce((select jsonb_agg(jsonb_build_object(
    'id',cat.id,'scope',cat.scope,'label',cat.label,'sortOrder',cat.sort_order,'active',cat.is_active
  ) order by cat.scope,cat.sort_order,cat.label) from public.academic_calendar_categories cat),'[]'::jsonb),
  'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct trim(s.school) school from public.students s where nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'school',null,'subject',coalesce(sub.name,c.subject),'teacherIds',coalesce((select jsonb_agg(ct.profile_id) from public.class_teachers ct where ct.class_id=c.id),'[]'::jsonb)) order by c.name) from public.classes c left join public.academy_subjects sub on sub.id=c.subject_id where c.active and (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))),'[]'::jsonb),
  'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','manager') and (public.current_user_role()='admin' or p.id=auth.uid())),'[]'::jsonb)
 );
end $$;

create or replace function public.admin_save_academic_calendar_category(
 p_id text,p_scope text,p_label text
) returns text language plpgsql security definer set search_path=public as $$
declare v_id text; v_label text:=trim(coalesce(p_label,''));
begin
 if auth.uid() is null or public.current_user_role()<>'admin' then raise exception '관리자만 일정 카테고리를 수정할 수 있습니다.'; end if;
 if p_scope not in ('school','academy') then raise exception '일정 구분을 확인해 주세요.'; end if;
 if char_length(v_label) not between 1 and 30 then raise exception '카테고리 이름은 1~30자로 입력해 주세요.'; end if;
 if p_id is null then
   v_id:='calendar_'||replace(gen_random_uuid()::text,'-','');
   insert into public.academic_calendar_categories(id,scope,label,sort_order)
   values(v_id,p_scope,v_label,coalesce((select max(sort_order)+10 from public.academic_calendar_categories where scope=p_scope),10));
 else
   update public.academic_calendar_categories set label=v_label,updated_at=now()
   where id=p_id and scope=p_scope returning id into v_id;
   if v_id is null then raise exception '수정할 카테고리를 찾지 못했습니다.'; end if;
 end if;
 return v_id;
exception when unique_violation then
 raise exception '같은 이름의 카테고리가 이미 있습니다.';
end $$;

create or replace function public.admin_set_academic_calendar_category_active(
 p_id text,p_active boolean
) returns void language plpgsql security definer set search_path=public as $$
declare v_scope text;
begin
 if auth.uid() is null or public.current_user_role()<>'admin' then raise exception '관리자만 일정 카테고리를 삭제하거나 복구할 수 있습니다.'; end if;
 select scope into v_scope from public.academic_calendar_categories where id=p_id for update;
 if v_scope is null then raise exception '카테고리를 찾지 못했습니다.'; end if;
 if not p_active and (select count(*) from public.academic_calendar_categories where scope=v_scope and is_active)>1 then
   update public.academic_calendar_categories set is_active=false,updated_at=now() where id=p_id;
 elsif not p_active then
   raise exception '일정 종류는 구분별로 최소 1개가 필요합니다.';
 else
   update public.academic_calendar_categories set is_active=true,updated_at=now() where id=p_id;
 end if;
end $$;

create or replace function public.staff_save_calendar_event(
 p_id uuid,p_scope text,p_school text,p_grade text,p_category text,p_title text,
 p_starts_on date,p_ends_on date,p_starts_at time,p_ends_at time,p_class_id uuid,
 p_teacher_id uuid,p_note text,p_contact_name text,p_contact_phone text,
 p_location text,p_status text
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_role public.user_role:=public.current_user_role();
begin
 if auth.uid() is null or not public.is_staff() or v_role='assistant' then raise exception '일정 저장 권한이 없습니다.'; end if;
 if p_scope not in ('school','academy') then raise exception '일정 구분을 확인해 주세요.'; end if;
 if not exists(select 1 from public.academic_calendar_categories cat where cat.id=p_category and cat.scope=p_scope and (cat.is_active or exists(select 1 from public.academic_calendar_events old where old.id=p_id and old.category=cat.id))) then raise exception '사용 가능한 일정 종류를 선택해 주세요.'; end if;
 if nullif(trim(p_title),'') is null then raise exception '일정명을 입력해 주세요.'; end if;
 if p_scope='school' and nullif(trim(p_school),'') is null then raise exception '학교를 입력해 주세요.'; end if;
 if p_status not in ('scheduled','completed','enrolled','cancelled','no_show') then raise exception '진행 상태를 확인해 주세요.'; end if;
 if p_ends_on<p_starts_on then raise exception '종료일을 확인해 주세요.'; end if;
 if (p_starts_at is null)<>(p_ends_at is null) or (p_starts_at is not null and p_ends_at<=p_starts_at) then raise exception '일정 시간을 확인해 주세요.'; end if;
 if p_class_id is not null and v_role<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then raise exception '담당 클래스만 연결할 수 있습니다.'; end if;
 if p_teacher_id is not null and v_role<>'admin' and p_teacher_id<>auth.uid() then raise exception '본인 일정만 등록할 수 있습니다.'; end if;
 if p_id is null then
  insert into public.academic_calendar_events(event_scope,school,grade,category,title,starts_on,ends_on,starts_at,ends_at,class_id,teacher_profile_id,note,contact_name,contact_phone,location,status,created_by)
  values(p_scope,nullif(trim(p_school),''),nullif(trim(p_grade),''),p_category,trim(p_title),p_starts_on,p_ends_on,p_starts_at,p_ends_at,p_class_id,coalesce(p_teacher_id,auth.uid()),nullif(trim(p_note),''),nullif(trim(p_contact_name),''),nullif(trim(p_contact_phone),''),nullif(trim(p_location),''),p_status,auth.uid()) returning id into v_id;
 else
  update public.academic_calendar_events set event_scope=p_scope,school=nullif(trim(p_school),''),grade=nullif(trim(p_grade),''),category=p_category,title=trim(p_title),starts_on=p_starts_on,ends_on=p_ends_on,starts_at=p_starts_at,ends_at=p_ends_at,class_id=p_class_id,teacher_profile_id=coalesce(p_teacher_id,auth.uid()),note=nullif(trim(p_note),''),contact_name=nullif(trim(p_contact_name),''),contact_phone=nullif(trim(p_contact_phone),''),location=nullif(trim(p_location),''),status=p_status,updated_at=now()
  where id=p_id and (created_by=auth.uid() or v_role='admin') returning id into v_id;
  if v_id is null then raise exception '수정 권한이 없습니다.'; end if;
 end if;
 return v_id;
end $$;

revoke all on function public.admin_save_academic_calendar_category(text,text,text),public.admin_set_academic_calendar_category_active(text,boolean) from public,anon;
grant execute on function public.admin_save_academic_calendar_category(text,text,text),public.admin_set_academic_calendar_category_active(text,boolean) to authenticated;
revoke all on function public.staff_academic_calendar_board(integer),public.staff_save_calendar_event(uuid,text,text,text,text,text,date,date,time,time,uuid,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.staff_academic_calendar_board(integer),public.staff_save_calendar_event(uuid,text,text,text,text,text,date,date,time,time,uuid,uuid,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
