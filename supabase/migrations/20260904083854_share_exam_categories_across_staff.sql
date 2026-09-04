-- Share one academy-wide exam category list across all active staff accounts.

drop index if exists public.exam_categories_owner_name_key;

create unique index if not exists exam_categories_shared_name_key
  on public.exam_categories ((lower(trim(name))));

create or replace function public.staff_exam_categories()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 시험 카테고리를 확인할 수 있습니다.';
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
    where is_active = true
  ), '[]'::jsonb);
end
$$;

create or replace function public.staff_add_exam_category(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_name text := nullif(trim(p_name), '');
begin
  if not public.is_staff() then
    raise exception '교직원만 시험 카테고리를 추가할 수 있습니다.';
  end if;
  if v_name is null then
    raise exception '카테고리 이름을 입력해 주세요.';
  end if;

  insert into public.exam_categories(owner_profile_id, name, is_active, sort_order)
  values(
    auth.uid(),
    v_name,
    true,
    coalesce((select max(sort_order) + 1 from public.exam_categories), 1)
  )
  on conflict ((lower(trim(name)))) do update
    set name = excluded.name,
        is_active = true,
        updated_at = now()
  returning id into v_id;

  return v_id;
end
$$;

create or replace function public.staff_set_exam_category(
  p_id uuid,
  p_name text,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(p_name), '');
begin
  if not public.is_staff() then
    raise exception '교직원만 시험 카테고리를 수정할 수 있습니다.';
  end if;

  if p_active = false then
    delete from public.exam_categories where id = p_id;
    if not found then
      raise exception '시험 카테고리를 찾지 못했습니다.';
    end if;
    return;
  end if;

  if v_name is null then
    raise exception '카테고리 이름을 입력해 주세요.';
  end if;

  update public.exam_categories
  set name = v_name,
      is_active = true,
      updated_at = now()
  where id = p_id;

  if not found then
    raise exception '시험 카테고리를 찾지 못했습니다.';
  end if;
end
$$;

revoke all on function public.staff_exam_categories() from public, anon;
revoke all on function public.staff_add_exam_category(text) from public, anon;
revoke all on function public.staff_set_exam_category(uuid, text, boolean) from public, anon;

grant execute on function public.staff_exam_categories() to authenticated;
grant execute on function public.staff_add_exam_category(text) to authenticated;
grant execute on function public.staff_set_exam_category(uuid, text, boolean) to authenticated;
