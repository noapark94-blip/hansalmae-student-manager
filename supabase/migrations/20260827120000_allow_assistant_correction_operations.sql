-- 조교 계정은 첨삭 운영 화면에서 학생을 배정하고 기록할 수 있습니다.
-- 다른 담당자 테이블의 기존 관리자·선생님 제한은 그대로 유지합니다.

create or replace function public.require_staff_profile()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  row_data jsonb := to_jsonb(new);
  target_profile_id uuid;
  allowed_roles text[];
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

  allowed_roles := case
    when tg_table_name='correction_assignments' then array['admin','teacher','assistant']::text[]
    else array['admin','teacher']::text[]
  end;

  if not exists (
    select 1
    from public.profiles p
    where p.id=target_profile_id
      and p.is_active
      and p.role::text=any(allowed_roles)
  ) then
    if tg_table_name='correction_assignments' then
      raise exception '활성 관리자·선생님·조교 계정만 첨삭 담당자로 배정할 수 있습니다.';
    end if;
    raise exception '로그인한 관리자 또는 선생님 계정만 담당자로 배정할 수 있습니다.';
  end if;

  return new;
end
$$;

revoke all on function public.require_staff_profile() from public, anon;

notify pgrst,'reload schema';
