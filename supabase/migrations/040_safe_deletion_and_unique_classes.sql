-- 같은 이름의 활성 클래스 생성을 막고, 운영 기록을 보호하면서 클래스를 정리합니다.
create or replace function public.staff_create_my_class(p_name text,p_subject_id uuid,p_room text default null,p_color text default '#922D61') returns uuid
language plpgsql security definer set search_path=public as $$
declare subject_row public.academy_subjects; result_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 클래스를 만들 수 있습니다.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '클래스 이름을 입력해 주세요.'; end if;
  if exists(select 1 from public.classes where active and lower(regexp_replace(name,'\\s+','','g'))=lower(regexp_replace(trim(p_name),'\\s+','','g'))) then
    raise exception '같은 이름의 클래스가 이미 있습니다.';
  end if;
  select * into subject_row from public.academy_subjects where id=p_subject_id and active;
  if subject_row.id is null then raise exception '사용 가능한 과목을 선택해 주세요.'; end if;
  insert into public.classes(name,subject,subject_id,room,color) values(trim(p_name),subject_row.name,subject_row.id,nullif(trim(p_room),''),coalesce(nullif(trim(p_color),''),'#922D61')) returning id into result_id;
  insert into public.class_teachers(class_id,profile_id) values(result_id,auth.uid());
  return result_id;
end $$;

revoke all on function public.staff_create_my_class(text,uuid,text,text) from public;
grant execute on function public.staff_create_my_class(text,uuid,text,text) to authenticated;

create or replace function public.staff_archive_class(p_class_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then raise exception '담당 클래스만 운영 종료할 수 있습니다.'; end if;
  update public.classes set active=false where id=p_class_id;
end $$;

create or replace function public.admin_delete_empty_class(p_class_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 클래스를 완전 삭제할 수 있습니다.'; end if;
  if exists(select 1 from public.enrollments where class_id=p_class_id) or exists(select 1 from public.class_schedules where class_id=p_class_id) or exists(select 1 from public.lessons where class_id=p_class_id) or exists(select 1 from public.assignments where class_id=p_class_id) then raise exception '학생·시간표·수업 기록이 있는 클래스는 삭제할 수 없습니다. 운영 종료를 사용해 주세요.'; end if;
  delete from public.classes where id=p_class_id;
end $$;

revoke all on function public.staff_archive_class(uuid),public.admin_delete_empty_class(uuid) from public;
grant execute on function public.staff_archive_class(uuid),public.admin_delete_empty_class(uuid) to authenticated;
