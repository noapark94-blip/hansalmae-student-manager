-- 서로 다른 행 구조를 사용하는 담당자 검증 트리거가 존재하지 않는 필드를
-- 직접 참조하지 않도록 JSON 표현에서 필요한 키만 안전하게 읽습니다.
create or replace function public.require_staff_profile()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  row_data jsonb := to_jsonb(new);
  target_profile_id uuid;
begin
  target_profile_id := case tg_table_name
    when 'class_teachers' then nullif(row_data ->> 'profile_id','')::uuid
    when 'vehicle_runs' then nullif(row_data ->> 'manager_profile_id','')::uuid
    when 'correction_assignments' then nullif(row_data ->> 'teacher_profile_id','')::uuid
    else null
  end;

  if target_profile_id is null then
    raise exception '담당자 계정 정보를 확인할 수 없습니다.';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id=target_profile_id
      and p.role in ('admin','teacher')
  ) then
    raise exception '로그인한 관리자 또는 선생님 계정만 담당자로 배정할 수 있습니다.';
  end if;

  return new;
end
$$;
