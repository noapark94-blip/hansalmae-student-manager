-- Keep unpublished revisions out of the broadly readable lessons table.

create table if not exists public.class_lesson_revision_drafts (
  lesson_id uuid primary key references public.lessons(id) on delete cascade,
  payload jsonb not null,
  saved_at timestamptz not null default now(),
  saved_by uuid references public.profiles(id) on delete set null
);

alter table public.class_lesson_revision_drafts enable row level security;
revoke all on table public.class_lesson_revision_drafts from public, anon, authenticated;

insert into public.class_lesson_revision_drafts(lesson_id,payload,saved_at,saved_by)
select id,revision_draft,coalesce(revision_saved_at,now()),revision_saved_by
from public.lessons
where revision_draft is not null
on conflict(lesson_id) do update
set payload=excluded.payload,saved_at=excluded.saved_at,saved_by=excluded.saved_by;

update public.lessons
set revision_draft=null,revision_saved_at=null,revision_saved_by=null
where revision_draft is not null;

create or replace function public.staff_class_revision_draft(p_class_id uuid,p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare result jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 임시저장을 확인할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;

  select jsonb_build_object(
    'payload',d.payload,
    'savedAt',d.saved_at,
    'savedBy',coalesce(p.display_name,'담당 선생님')
  )
  into result
  from public.lessons l
  join public.class_lesson_revision_drafts d on d.lesson_id=l.id
  left join public.profiles p on p.id=d.saved_by
  where l.class_id=p_class_id and l.lesson_date=p_date and l.status='completed'
  order by l.starts_at
  limit 1;

  return result;
end;
$$;

create or replace function public.staff_save_class_revision_draft(
  p_class_id uuid,
  p_date date,
  p_payload jsonb
)
returns timestamptz
language plpgsql
security definer
set search_path=public
as $$
declare v_lesson_id uuid; v_saved_at timestamptz:=now();
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 임시저장할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(coalesce(p_payload->'rows','null'::jsonb))<>'array' then
    raise exception '임시저장할 수업 내용을 확인해 주세요.';
  end if;

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date and status='completed'
  order by starts_at
  limit 1;
  if v_lesson_id is null then
    raise exception '완료된 수업만 수정 임시저장할 수 있습니다.';
  end if;

  insert into public.class_lesson_revision_drafts(lesson_id,payload,saved_at,saved_by)
  values(v_lesson_id,p_payload,v_saved_at,auth.uid())
  on conflict(lesson_id) do update
  set payload=excluded.payload,saved_at=excluded.saved_at,saved_by=excluded.saved_by;

  return v_saved_at;
end;
$$;

alter function public.staff_publish_class_revision(uuid,date,jsonb)
  rename to staff_apply_class_revision_payload;

revoke all on function public.staff_apply_class_revision_payload(uuid,date,jsonb)
from public,anon,authenticated;

create or replace function public.staff_publish_class_revision(
  p_class_id uuid,
  p_date date,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_lesson_id uuid;
begin
  perform public.staff_apply_class_revision_payload(p_class_id,p_date,p_payload);

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date and status='completed'
  order by starts_at
  limit 1;

  delete from public.class_lesson_revision_drafts where lesson_id=v_lesson_id;
end;
$$;

revoke all on function public.staff_class_revision_draft(uuid,date) from public,anon;
revoke all on function public.staff_save_class_revision_draft(uuid,date,jsonb) from public,anon;
revoke all on function public.staff_publish_class_revision(uuid,date,jsonb) from public,anon;
grant execute on function public.staff_class_revision_draft(uuid,date) to authenticated;
grant execute on function public.staff_save_class_revision_draft(uuid,date,jsonb) to authenticated;
grant execute on function public.staff_publish_class_revision(uuid,date,jsonb) to authenticated;

notify pgrst,'reload schema';
