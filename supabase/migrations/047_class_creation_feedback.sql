-- 클래스 생성 전에 공백·대소문자를 무시한 동일 이름을 확인합니다.
create or replace function public.staff_class_name_conflict(p_name text)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select case
    when not public.is_staff() then false
    else exists(
      select 1
      from public.classes c
      where c.active
        and lower(regexp_replace(c.name,'[[:space:]]+','','g')) = lower(regexp_replace(trim(p_name),'[[:space:]]+','','g'))
    )
  end
$$;

revoke all on function public.staff_class_name_conflict(text) from public;
grant execute on function public.staff_class_name_conflict(text) to authenticated;
