create table if not exists public.app_menu_settings (
  id text primary key check (id = 'main'),
  layout jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

alter table public.app_menu_settings enable row level security;

insert into public.app_menu_settings(id, layout)
values (
  'main',
  '{"folders":[
    {"id":"main","name":"바로가기","itemIds":["dashboard"]},
    {"id":"students","name":"학생 관리","itemIds":["students","bulk-import","bulk-accounts","guide"]},
    {"id":"schedules","name":"시간표","itemIds":["schedule","corrections","transport"]},
    {"id":"classes","name":"수업 관리","itemIds":["attendance","makeups","assignments","consultations"]},
    {"id":"operations","name":"학원 운영","itemIds":["communications","tuition","tuition-settings","analytics","backup","audit"]},
    {"id":"accounts","name":"계정 설정","itemIds":["settings","my-account"]}
  ]}'::jsonb
)
on conflict (id) do nothing;

create or replace function public.get_app_menu_layout()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select layout from public.app_menu_settings where id = 'main';
$$;

create or replace function public.admin_save_app_menu_layout(p_layout jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() <> 'admin' then
    raise exception '관리자만 메뉴 구성을 변경할 수 있습니다.';
  end if;
  if jsonb_typeof(p_layout) <> 'object'
    or jsonb_typeof(p_layout->'folders') <> 'array'
    or jsonb_array_length(p_layout->'folders') = 0 then
    raise exception '메뉴 폴더 구성이 올바르지 않습니다.';
  end if;

  insert into public.app_menu_settings(id, layout, updated_at, updated_by)
  values ('main', p_layout, now(), auth.uid())
  on conflict (id) do update
  set layout = excluded.layout,
      updated_at = excluded.updated_at,
      updated_by = excluded.updated_by;
  return p_layout;
end;
$$;

revoke all on function public.get_app_menu_layout() from public;
revoke all on function public.admin_save_app_menu_layout(jsonb) from public;
grant execute on function public.get_app_menu_layout() to authenticated;
grant execute on function public.admin_save_app_menu_layout(jsonb) to authenticated;
