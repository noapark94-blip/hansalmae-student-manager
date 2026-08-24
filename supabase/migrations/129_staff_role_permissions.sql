create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce((select role in ('admin','teacher','assistant','manager') and is_active from public.profiles where id=auth.uid()),false) $$;

create or replace function public.can_manage_vehicle()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce((select role in ('admin','manager') and is_active from public.profiles where id=auth.uid()),false) $$;
revoke all on function public.can_manage_vehicle() from public;
grant execute on function public.can_manage_vehicle() to authenticated;

alter table public.account_invites drop constraint if exists account_invites_role_check;
alter table public.account_invites drop constraint if exists account_invites_check;
alter table public.account_invites add constraint account_invites_role_check check (role in ('teacher','assistant','manager','student','guardian'));
alter table public.account_invites add constraint account_invites_target_check check ((role in ('student','guardian') and student_id is not null) or (role in ('teacher','assistant','manager') and student_id is null));

create or replace function public.admin_update_account(p_profile_id uuid,p_display_name text,p_phone text,p_role public.user_role,p_is_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare previous_role public.user_role; previous_active boolean;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 계정을 변경할 수 있습니다.'; end if;
  if nullif(trim(p_display_name),'') is null then raise exception '표시 이름을 입력해 주세요.'; end if;
  select role,is_active into previous_role,previous_active from public.profiles where id=p_profile_id;
  if previous_role is null then raise exception '계정을 찾을 수 없습니다.'; end if;
  if p_profile_id=auth.uid() and (p_role<>'admin' or not p_is_active) then raise exception '현재 로그인한 관리자 본인의 역할이나 활성 상태는 변경할 수 없습니다.'; end if;
  if p_role<>'student' then update public.students set profile_id=null where profile_id=p_profile_id; end if;
  if p_role<>'guardian' then update public.guardians set profile_id=null where profile_id=p_profile_id; end if;
  if p_role not in ('teacher','assistant','manager') then update public.teachers set profile_id=null where profile_id=p_profile_id; end if;
  update public.profiles set display_name=trim(p_display_name),phone=nullif(trim(p_phone),''),role=p_role,is_active=p_is_active where id=p_profile_id;
  if p_role in ('teacher','assistant','manager') and not exists(select 1 from public.teachers where profile_id=p_profile_id) then insert into public.teachers(profile_id,name) values(p_profile_id,trim(p_display_name));
  elsif p_role in ('teacher','assistant','manager') then update public.teachers set name=trim(p_display_name) where profile_id=p_profile_id; end if;
  insert into public.account_change_logs(changed_by,target_profile_id,action,details) values(auth.uid(),p_profile_id,'account_updated',jsonb_build_object('previousRole',previous_role,'role',p_role,'previousActive',previous_active,'isActive',p_is_active));
end $$;

create or replace function public.admin_issue_account_invite(p_role public.user_role,p_student_id uuid default null,p_valid_days integer default 14)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare chars constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; plain_code text:=''; invite_id uuid; target_name text; i integer;
begin
 if public.current_user_role()<>'admin' then raise exception '관리자만 초대코드를 발급할 수 있습니다.'; end if;
 if p_role not in ('teacher','assistant','manager','student','guardian') then raise exception '가입 역할을 선택해 주세요.'; end if;
 if p_valid_days<1 or p_valid_days>30 then raise exception '유효기간은 1~30일로 설정해 주세요.'; end if;
 if p_role in ('student','guardian') then
   select name into target_name from public.students where id=p_student_id and status in ('active','재원');
   if target_name is null then raise exception '연결할 재원 학생을 선택해 주세요.'; end if;
   if p_role='student' and exists(select 1 from public.students where id=p_student_id and profile_id is not null) then raise exception '이미 로그인 계정이 연결된 학생입니다.'; end if;
   update public.account_invites set revoked_at=now() where role=p_role and student_id=p_student_id and used_at is null and revoked_at is null and expires_at>now();
 else target_name:=case p_role when 'assistant' then '새 조교' when 'manager' then '새 실장님' else '새 선생님' end; end if;
 loop plain_code:=''; for i in 1..8 loop plain_code:=plain_code||substr(chars,1+floor(random()*length(chars))::integer,1); end loop; exit when not exists(select 1 from public.account_invites where code_hash=digest(plain_code,'sha256')); end loop;
 insert into public.account_invites(code_hash,code_hint,role,student_id,created_by,expires_at) values(digest(plain_code,'sha256'),right(plain_code,4),p_role,case when p_role in ('student','guardian') then p_student_id else null end,auth.uid(),now()+make_interval(days=>p_valid_days)) returning id into invite_id;
 return jsonb_build_object('id',invite_id,'code',plain_code,'role',p_role,'targetName',target_name,'expiresAt',now()+make_interval(days=>p_valid_days));
end $$;

do $$ declare t text; begin
 foreach t in array array['vehicle_runs','vehicle_boardings','vehicle_run_exceptions','vehicle_schedule_exclusions','vehicle_manual_assignments','vehicle_schedule_notes'] loop
   execute format('drop policy if exists staff_manage_%I on public.%I',t,t);
 end loop;
end $$;

drop policy if exists staff_manage_vehicle_runs on public.vehicle_runs;
drop policy if exists staff_manage_vehicle_boardings on public.vehicle_boardings;
drop policy if exists staff_manage_vehicle_run_exceptions on public.vehicle_run_exceptions;
drop policy if exists vehicle_schedule_exclusions_staff on public.vehicle_schedule_exclusions;
drop policy if exists vehicle_manual_assignments_staff on public.vehicle_manual_assignments;
drop policy if exists vehicle_schedule_notes_staff on public.vehicle_schedule_notes;

create policy vehicle_runs_read on public.vehicle_runs for select to authenticated using(public.is_staff());
create policy vehicle_runs_write on public.vehicle_runs for all to authenticated using(public.can_manage_vehicle()) with check(public.can_manage_vehicle());
create policy vehicle_boardings_read on public.vehicle_boardings for select to authenticated using(public.is_staff());
create policy vehicle_boardings_write on public.vehicle_boardings for all to authenticated using(public.can_manage_vehicle()) with check(public.can_manage_vehicle());
create policy vehicle_run_exceptions_read on public.vehicle_run_exceptions for select to authenticated using(public.is_staff());
create policy vehicle_run_exceptions_write on public.vehicle_run_exceptions for all to authenticated using(public.can_manage_vehicle()) with check(public.can_manage_vehicle());
create policy vehicle_schedule_exclusions_read on public.vehicle_schedule_exclusions for select to authenticated using(public.is_staff());
create policy vehicle_schedule_exclusions_write on public.vehicle_schedule_exclusions for all to authenticated using(public.can_manage_vehicle()) with check(public.can_manage_vehicle());
create policy vehicle_manual_assignments_read on public.vehicle_manual_assignments for select to authenticated using(public.is_staff());
create policy vehicle_manual_assignments_write on public.vehicle_manual_assignments for all to authenticated using(public.can_manage_vehicle()) with check(public.can_manage_vehicle());
create policy vehicle_schedule_notes_read on public.vehicle_schedule_notes for select to authenticated using(public.is_staff());
create policy vehicle_schedule_notes_write on public.vehicle_schedule_notes for all to authenticated using(public.can_manage_vehicle()) with check(public.can_manage_vehicle());

create or replace function public.staff_set_vehicle_schedule_exclusion(p_student_id uuid,p_weekday smallint,p_direction text,p_excluded boolean)
returns void language plpgsql security definer set search_path=public as $$ begin
 if not public.can_manage_vehicle() then raise exception '관리자 또는 실장님만 차량 이용 여부를 변경할 수 있습니다.'; end if;
 if p_weekday not between 1 and 5 then raise exception '차량 운행 요일을 확인해 주세요.'; end if;
 if p_direction not in ('pickup','dropoff') then raise exception '등원·하원 구분을 확인해 주세요.'; end if;
 if p_excluded then insert into public.vehicle_schedule_exclusions(student_id,weekday,direction,created_by) values(p_student_id,p_weekday,p_direction,auth.uid()) on conflict(student_id,weekday,direction) do nothing;
 else delete from public.vehicle_schedule_exclusions where student_id=p_student_id and weekday=p_weekday and direction=p_direction; end if;
end $$;

create or replace function public.staff_save_manual_vehicle_assignment(p_student_id uuid,p_weekday smallint,p_direction text,p_time time,p_remove boolean default false)
returns void language plpgsql security definer set search_path=public as $$ begin
 if not public.can_manage_vehicle() then raise exception '관리자 또는 실장님만 차량 직접 배정을 변경할 수 있습니다.'; end if;
 if p_weekday not between 1 and 5 or p_direction not in ('pickup','dropoff') or p_time not in (time '16:00',time '17:30',time '19:00',time '20:30') then raise exception '차량 배정 정보를 확인해 주세요.'; end if;
 if p_remove then delete from public.vehicle_manual_assignments where student_id=p_student_id and weekday=p_weekday and direction=p_direction;
 else insert into public.vehicle_manual_assignments(student_id,weekday,direction,vehicle_time,created_by) values(p_student_id,p_weekday,p_direction,p_time,auth.uid()) on conflict(student_id,weekday,direction) do update set vehicle_time=excluded.vehicle_time,updated_at=now(),created_by=auth.uid(); delete from public.vehicle_schedule_exclusions where student_id=p_student_id and weekday=p_weekday and direction=p_direction; end if;
end $$;

create or replace function public.staff_save_vehicle_run(p_run_id uuid,p_manager_id uuid,p_weekday smallint,p_pickup_time time,p_pickup_location text,p_student_ids uuid[],p_route_name text,p_direction text,p_stop_order smallint)
returns uuid language plpgsql security definer set search_path=public as $$ declare saved_id uuid; student_id uuid; begin
 if not public.can_manage_vehicle() then raise exception '관리자 또는 실장님만 차량 운행을 변경할 수 있습니다.'; end if;
 if nullif(trim(p_route_name),'') is null or nullif(trim(p_pickup_location),'') is null or p_direction not in ('pickup','dropoff') or p_stop_order not between 1 and 99 then raise exception '차량 운행 정보를 확인해 주세요.'; end if;
 if p_run_id is null then insert into public.vehicle_runs(manager_profile_id,weekday,pickup_time,pickup_location,route_name,direction,stop_order) values(p_manager_id,p_weekday,p_pickup_time,trim(p_pickup_location),trim(p_route_name),p_direction,p_stop_order) returning id into saved_id;
 else update public.vehicle_runs set manager_profile_id=p_manager_id,weekday=p_weekday,pickup_time=p_pickup_time,pickup_location=trim(p_pickup_location),route_name=trim(p_route_name),direction=p_direction,stop_order=p_stop_order,active=true where id=p_run_id returning id into saved_id; end if;
 delete from public.vehicle_boardings where run_id=saved_id;
 foreach student_id in array coalesce(p_student_ids,array[]::uuid[]) loop insert into public.vehicle_boardings(run_id,student_id) values(saved_id,student_id); end loop;
 return saved_id;
end $$;

notify pgrst,'reload schema';
