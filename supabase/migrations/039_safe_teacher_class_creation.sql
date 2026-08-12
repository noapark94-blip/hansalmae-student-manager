-- 클래스 생성과 현재 담당자 배정을 한 트랜잭션에서 처리합니다.
-- 직전 화면에서 클래스만 생성된 경우에는 같은 클래스를 찾아 담당자 연결만 복구합니다.

create or replace function public.staff_create_my_class(
  p_name text,
  p_subject_id uuid,
  p_room text default null,
  p_color text default '#922D61'
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  subject_row public.academy_subjects;
  result_id uuid;
begin
  if not public.is_staff() then
    raise exception '교직원만 클래스를 만들 수 있습니다.';
  end if;
  if nullif(trim(p_name),'') is null then
    raise exception '클래스 이름을 입력해 주세요.';
  end if;

  select * into subject_row
  from public.academy_subjects
  where id=p_subject_id and active;
  if subject_row.id is null then
    raise exception '사용 가능한 과목을 선택해 주세요.';
  end if;

  select c.id into result_id
  from public.classes c
  where c.active
    and lower(c.name)=lower(trim(p_name))
    and c.subject_id=p_subject_id
    and coalesce(c.room,'')=coalesce(nullif(trim(p_room),''),'')
  order by c.created_at desc
  limit 1;

  if result_id is null then
    insert into public.classes(name,subject,subject_id,room,color)
    values(trim(p_name),subject_row.name,subject_row.id,nullif(trim(p_room),''),coalesce(nullif(trim(p_color),''),'#922D61'))
    returning id into result_id;
  end if;

  insert into public.class_teachers(class_id,profile_id)
  values(result_id,auth.uid())
  on conflict do nothing;

  return result_id;
end
$$;

revoke all on function public.staff_create_my_class(text,uuid,text,text) from public;
grant execute on function public.staff_create_my_class(text,uuid,text,text) to authenticated;
