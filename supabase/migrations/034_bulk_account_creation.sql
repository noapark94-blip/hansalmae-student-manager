-- 계정 일괄 생성용 참조 데이터, 교사 클래스 연결과 작업 이력을 제공합니다.
create table public.bulk_account_import_logs(
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  file_name text,
  account_count integer not null check(account_count between 1 and 50),
  created_at timestamptz not null default now()
);
alter table public.bulk_account_import_logs enable row level security;
create policy "admin_read_bulk_account_logs" on public.bulk_account_import_logs for select to authenticated using(public.current_user_role()='admin');
revoke all on public.bulk_account_import_logs from anon,authenticated;
grant select on public.bulk_account_import_logs to authenticated;

create or replace function public.admin_bulk_account_reference()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 계정 일괄 등록을 사용할 수 있습니다.';end if;
  return jsonb_build_object(
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'linked',s.profile_id is not null) order by s.name) from public.students s where s.status in('active','재원')),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'subject',c.subject) order by c.name) from public.classes c where c.active),'[]'::jsonb)
  );
end $$;

create or replace function public.admin_set_teacher_classes(p_profile_id uuid,p_class_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare class_id uuid;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 교사 클래스를 연결할 수 있습니다.';end if;
  if not exists(select 1 from public.profiles p where p.id=p_profile_id and p.role='teacher') then raise exception '교사 역할 계정을 선택해 주세요.';end if;
  delete from public.class_teachers where profile_id=p_profile_id;
  foreach class_id in array coalesce(p_class_ids,array[]::uuid[]) loop
    if not exists(select 1 from public.classes c where c.id=class_id and c.active) then raise exception '연결할 클래스를 찾을 수 없습니다.';end if;
    insert into public.class_teachers(class_id,profile_id) values(class_id,p_profile_id) on conflict do nothing;
  end loop;
  insert into public.account_change_logs(changed_by,target_profile_id,action,details) values(auth.uid(),p_profile_id,'teacher_classes_changed',jsonb_build_object('classIds',coalesce(p_class_ids,array[]::uuid[])));
end $$;

create or replace function public.admin_log_bulk_account_import(p_file_name text,p_account_count integer)
returns void language plpgsql security definer set search_path=public as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 계정 일괄 등록 이력을 저장할 수 있습니다.';end if;
  if p_account_count not between 1 and 50 then raise exception '한 번에 1~50개 계정까지 등록할 수 있습니다.';end if;
  insert into public.bulk_account_import_logs(requested_by,file_name,account_count) values(auth.uid(),nullif(trim(p_file_name),''),p_account_count);
end $$;

revoke all on function public.admin_bulk_account_reference() from public;
revoke all on function public.admin_set_teacher_classes(uuid,uuid[]) from public;
revoke all on function public.admin_log_bulk_account_import(text,integer) from public;
grant execute on function public.admin_bulk_account_reference() to authenticated;
grant execute on function public.admin_set_teacher_classes(uuid,uuid[]) to authenticated;
grant execute on function public.admin_log_bulk_account_import(text,integer) to authenticated;
