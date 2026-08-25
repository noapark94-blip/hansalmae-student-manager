-- 초대코드가 없는 학부모의 자녀 연결 요청과 관리자 승인 흐름
create table public.guardian_link_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  guardian_name text not null,
  guardian_phone text not null,
  student_name text not null,
  school text,
  grade text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  matched_student_id uuid references public.students(id) on delete set null,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(profile_id)
);

alter table public.guardian_link_requests enable row level security;
revoke all on table public.guardian_link_requests from anon,authenticated;

create index guardian_link_requests_status_created_idx
  on public.guardian_link_requests(status,created_at desc);

create or replace function public.admin_guardian_link_request_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 학부모 연결 요청을 확인할 수 있습니다.'; end if;
  return jsonb_build_object(
    'requests',coalesce((select jsonb_agg(jsonb_build_object(
      'id',r.id,'profileId',r.profile_id,'guardianName',r.guardian_name,'guardianPhone',r.guardian_phone,
      'studentName',r.student_name,'school',r.school,'grade',r.grade,'status',r.status,
      'matchedStudentId',r.matched_student_id,'createdAt',r.created_at
    ) order by r.created_at desc) from public.guardian_link_requests r where r.status='pending'),'[]'::jsonb),
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade
    ) order by s.name,s.school,s.grade) from public.students s where s.status in ('active','재원')),'[]'::jsonb)
  );
end $$;

create or replace function public.admin_resolve_guardian_link_request(
  p_request_id uuid,
  p_action text,
  p_student_id uuid default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  request_row public.guardian_link_requests%rowtype;
  guardian_id uuid;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 학부모 연결 요청을 처리할 수 있습니다.'; end if;
  if p_action not in ('approve','reject') then raise exception '승인 또는 거절을 선택해 주세요.'; end if;
  select * into request_row from public.guardian_link_requests where id=p_request_id and status='pending' for update;
  if request_row.id is null then raise exception '처리할 연결 요청을 찾을 수 없습니다.'; end if;

  if p_action='approve' then
    if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then
      raise exception '연결할 재원 학생을 선택해 주세요.';
    end if;
    select id into guardian_id from public.guardians where profile_id=request_row.profile_id limit 1;
    if guardian_id is null then
      insert into public.guardians(profile_id,name,phone)
      values(request_row.profile_id,request_row.guardian_name,request_row.guardian_phone)
      returning id into guardian_id;
    else
      update public.guardians set name=request_row.guardian_name,phone=request_row.guardian_phone where id=guardian_id;
    end if;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary)
    values(p_student_id,guardian_id,'보호자',true)
    on conflict(student_id,guardian_id) do update set relationship='보호자',is_primary=true;
    update public.profiles set role='guardian',display_name=request_row.guardian_name,phone=request_row.guardian_phone,is_active=true
    where id=request_row.profile_id;
    update public.guardian_link_requests set status='approved',matched_student_id=p_student_id,reviewed_by=auth.uid(),reviewed_at=now()
    where id=request_row.id;
  else
    update public.profiles set is_active=false where id=request_row.profile_id;
    update public.guardian_link_requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now()
    where id=request_row.id;
  end if;
end $$;

revoke all on function public.admin_guardian_link_request_board() from public;
revoke all on function public.admin_resolve_guardian_link_request(uuid,text,uuid) from public;
grant execute on function public.admin_guardian_link_request_board() to authenticated;
grant execute on function public.admin_resolve_guardian_link_request(uuid,text,uuid) to authenticated;

notify pgrst,'reload schema';
