-- 선생님은 자신의 클래스를, 관리자는 전체 클래스를 수정·운영 종료할 수 있습니다.

create or replace function public.staff_class_management_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 클래스 목록을 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'subject',c.subject,'subjectId',c.subject_id,'room',c.room,'color',c.color,'active',c.active,
    'enrollmentCount',(select count(*) from public.enrollments e where e.class_id=c.id),
    'scheduleCount',(select count(*) from public.class_schedules cs where cs.class_id=c.id),
    'lessonCount',(select count(*) from public.lessons l where l.class_id=c.id),
    'assignmentCount',(select count(*) from public.assignments a where a.class_id=c.id)
  ) order by c.active desc,c.subject,c.name)
  from public.classes c
  where public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid())),'[]'::jsonb);
end $$;

create or replace function public.staff_update_class(p_class_id uuid,p_name text,p_subject_id uuid,p_room text default null,p_color text default '#922D61')
returns void language plpgsql security definer set search_path=public as $$
declare subject_row public.academy_subjects;
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '클래스 이름을 입력해 주세요.'; end if;
  select * into subject_row from public.academy_subjects where id=p_subject_id and active;
  if subject_row.id is null then raise exception '사용 가능한 과목을 선택해 주세요.'; end if;
  if exists(select 1 from public.classes c where c.id<>p_class_id and c.active and lower(regexp_replace(c.name,'\s+','','g'))=lower(regexp_replace(trim(p_name),'\s+','','g'))) then raise exception '같은 이름의 클래스가 이미 있습니다.'; end if;
  update public.classes set name=trim(p_name),subject=subject_row.name,subject_id=subject_row.id,room=nullif(trim(p_room),''),color=coalesce(nullif(trim(p_color),''),'#922D61') where id=p_class_id;
  if not found then raise exception '클래스를 찾을 수 없습니다.'; end if;
end $$;

create or replace function public.staff_set_class_active(p_class_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare class_name text;
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then raise exception '담당 클래스만 운영 상태를 변경할 수 있습니다.'; end if;
  select name into class_name from public.classes where id=p_class_id;
  if class_name is null then raise exception '클래스를 찾을 수 없습니다.'; end if;
  if p_active and exists(select 1 from public.classes c where c.id<>p_class_id and c.active and lower(regexp_replace(c.name,'\s+','','g'))=lower(regexp_replace(class_name,'\s+','','g'))) then raise exception '같은 이름으로 운영 중인 클래스가 있어 다시 운영할 수 없습니다.'; end if;
  update public.classes set active=p_active where id=p_class_id;
end $$;

revoke all on function public.staff_class_management_board(),public.staff_update_class(uuid,text,uuid,text,text),public.staff_set_class_active(uuid,boolean) from public;
grant execute on function public.staff_class_management_board(),public.staff_update_class(uuid,text,uuid,text,text),public.staff_set_class_active(uuid,boolean) to authenticated;
