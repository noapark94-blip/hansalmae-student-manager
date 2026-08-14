-- 시험 카테고리의 '사용 중지' 동작을 영구 삭제로 전환합니다.
-- 기존 시험 기록은 exam_type 문자열로 보존되므로 카테고리를 삭제해도 과거 점수/기록은 유지됩니다.

create or replace function public.staff_exam_categories()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 시험 카테고리를 관리할 수 있습니다.';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'isActive', is_active,
        'sortOrder', sort_order
      ) order by sort_order, name
    )
    from public.exam_categories
    where owner_profile_id=auth.uid()
      and is_active=true
  ), '[]'::jsonb);
end $$;

create or replace function public.staff_set_exam_category(p_id uuid,p_name text,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 시험 카테고리를 수정할 수 있습니다.';
  end if;

  if p_active=false then
    delete from public.exam_categories
    where id=p_id and owner_profile_id=auth.uid();

    if not found then
      raise exception '시험 카테고리를 찾을 수 없습니다.';
    end if;
    return;
  end if;

  update public.exam_categories
  set name=trim(p_name), is_active=true, updated_at=now()
  where id=p_id and owner_profile_id=auth.uid();

  if not found then
    raise exception '시험 카테고리를 찾을 수 없습니다.';
  end if;
end $$;

-- 과거에 사용 중지해 둔 항목은 새 화면에서 다시 노출되지 않도록 정리합니다.
delete from public.exam_categories where is_active=false;

revoke all on function public.staff_exam_categories(), public.staff_set_exam_category(uuid,text,boolean) from public;
grant execute on function public.staff_exam_categories(), public.staff_set_exam_category(uuid,text,boolean) to authenticated;

notify pgrst,'reload schema';
