-- 고정 차량 노선, 승하차 정류장 순서, 날짜별 운행 변경을 관리합니다.

alter table public.vehicle_runs add column route_name text not null default '기본 노선';
alter table public.vehicle_runs add column direction text not null default 'pickup' check(direction in ('pickup','dropoff'));
alter table public.vehicle_runs add column stop_order smallint not null default 1 check(stop_order between 1 and 99);

create table public.vehicle_run_exceptions(
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.vehicle_runs(id) on delete cascade,
  service_date date not null,
  kind text not null check(kind in ('changed','cancelled')),
  pickup_time time,
  pickup_location text,
  note text,
  created_by uuid not null references public.profiles(id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  unique(run_id,service_date),
  check(kind='cancelled' or (pickup_time is not null and nullif(trim(pickup_location),'') is not null))
);
alter table public.vehicle_run_exceptions enable row level security;
create policy "staff_manage_vehicle_run_exceptions" on public.vehicle_run_exceptions for all to authenticated using(public.is_staff()) with check(public.is_staff());
grant select,insert,update,delete on table public.vehicle_run_exceptions to authenticated;

create function public.validate_vehicle_run_exception_date()
returns trigger language plpgsql security definer set search_path=public as $$
declare run_weekday smallint;target_manager uuid;
begin
  select weekday,manager_profile_id into run_weekday,target_manager from public.vehicle_runs where id=new.run_id;
  if new.service_date<current_date then raise exception '오늘 이후 날짜만 변경할 수 있습니다.';end if;
  if extract(isodow from new.service_date)::smallint<>run_weekday then raise exception '고정 운행 요일과 같은 날짜를 선택해 주세요.';end if;
  if new.kind='changed' and exists(select 1 from public.vehicle_runs vr where vr.id<>new.run_id and vr.active and vr.weekday=run_weekday and vr.pickup_time=new.pickup_time and vr.manager_profile_id=target_manager) then raise exception '차량실장님에게 변경 시간과 겹치는 운행이 있습니다.';end if;
  if new.kind='changed' and exists(select 1 from public.vehicle_boardings mine join public.vehicle_boardings other on other.student_id=mine.student_id and other.run_id<>new.run_id join public.vehicle_runs vr on vr.id=other.run_id where mine.run_id=new.run_id and vr.active and vr.weekday=run_weekday and vr.pickup_time=new.pickup_time) then raise exception '탑승 학생에게 변경 시간과 겹치는 차량 배정이 있습니다.';end if;
  return new;
end $$;
create trigger vehicle_exception_validate_date before insert or update on public.vehicle_run_exceptions for each row execute function public.validate_vehicle_run_exception_date();

create function public.prevent_duplicate_vehicle_boarding()
returns trigger language plpgsql security definer set search_path=public as $$
declare target public.vehicle_runs%rowtype;
begin
  select * into target from public.vehicle_runs where id=new.run_id;
  if exists(select 1 from public.vehicle_boardings vb join public.vehicle_runs vr on vr.id=vb.run_id where vb.student_id=new.student_id and vb.run_id<>new.run_id and vr.active and vr.weekday=target.weekday and vr.pickup_time=target.pickup_time) then
    raise exception '학생이 같은 요일·시간의 다른 차량에 이미 배정되어 있습니다.';
  end if;
  return new;
end $$;
create trigger vehicle_boarding_prevent_duplicate before insert or update on public.vehicle_boardings for each row execute function public.prevent_duplicate_vehicle_boarding();

drop function public.staff_save_vehicle_run(uuid,uuid,smallint,time,text,uuid[]);
create function public.staff_save_vehicle_run(p_run_id uuid,p_manager_id uuid,p_weekday smallint,p_pickup_time time,p_pickup_location text,p_student_ids uuid[],p_route_name text,p_direction text,p_stop_order smallint)
returns uuid language plpgsql security definer set search_path=public as $$
declare saved_id uuid;student_id uuid;
begin
  if not coalesce(public.is_staff(),false) then raise exception '교직원만 차량 운행을 등록할 수 있습니다.';end if;
  if nullif(trim(p_route_name),'') is null then raise exception '노선명을 입력해 주세요.';end if;
  if nullif(trim(p_pickup_location),'') is null then raise exception '탑승 위치를 입력해 주세요.';end if;
  if p_direction not in ('pickup','dropoff') then raise exception '승차·하차 구분을 확인해 주세요.';end if;
  if p_stop_order not between 1 and 99 then raise exception '정류장 순서를 확인해 주세요.';end if;
  if p_run_id is null then
    insert into public.vehicle_runs(manager_profile_id,weekday,pickup_time,pickup_location,route_name,direction,stop_order) values(p_manager_id,p_weekday,p_pickup_time,trim(p_pickup_location),trim(p_route_name),p_direction,p_stop_order) returning id into saved_id;
  else
    update public.vehicle_runs set manager_profile_id=p_manager_id,weekday=p_weekday,pickup_time=p_pickup_time,pickup_location=trim(p_pickup_location),route_name=trim(p_route_name),direction=p_direction,stop_order=p_stop_order,active=true where id=p_run_id returning id into saved_id;
    if saved_id is null then raise exception '차량 운행을 찾을 수 없습니다.';end if;
  end if;
  delete from public.vehicle_boardings where run_id=saved_id;
  foreach student_id in array coalesce(p_student_ids,array[]::uuid[]) loop insert into public.vehicle_boardings(run_id,student_id) values(saved_id,student_id);end loop;
  return saved_id;
end $$;

create function public.staff_vehicle_operations()
returns jsonb language sql stable security definer set search_path=public as $$
  with today as(select (now() at time zone 'Asia/Seoul')::date service_date,extract(isodow from now() at time zone 'Asia/Seoul')::smallint weekday)
  select case when public.is_staff() then jsonb_build_object(
    'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',vr.id,'managerId',p.id,'managerName',p.display_name,'weekday',vr.weekday,'pickupTime',vr.pickup_time,'pickupLocation',vr.pickup_location,'routeName',vr.route_name,'direction',vr.direction,'stopOrder',vr.stop_order,'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.vehicle_boardings vb join public.students s on s.id=vb.student_id where vb.run_id=vr.id and s.status in ('active','재원')),'[]'::jsonb)) order by vr.weekday,vr.route_name,vr.direction,vr.stop_order,vr.pickup_time) from public.vehicle_runs vr join public.profiles p on p.id=vr.manager_profile_id where vr.active),'[]'::jsonb),
    'vehicleExceptions',coalesce((select jsonb_agg(jsonb_build_object('id',ve.id,'runId',ve.run_id,'serviceDate',ve.service_date,'kind',ve.kind,'pickupTime',ve.pickup_time,'pickupLocation',ve.pickup_location,'note',ve.note) order by ve.service_date desc) from public.vehicle_run_exceptions ve where ve.service_date>=current_date-30),'[]'::jsonb),
    'todayVehicles',coalesce((select jsonb_agg(jsonb_build_object('id',vr.id,'managerId',p.id,'managerName',p.display_name,'routeName',vr.route_name,'direction',vr.direction,'stopOrder',vr.stop_order,'pickupTime',coalesce(ve.pickup_time,vr.pickup_time),'pickupLocation',coalesce(ve.pickup_location,vr.pickup_location),'changed',ve.kind='changed','students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.vehicle_boardings vb join public.students s on s.id=vb.student_id where vb.run_id=vr.id and s.status in ('active','재원')),'[]'::jsonb)) order by vr.route_name,vr.direction,vr.stop_order,coalesce(ve.pickup_time,vr.pickup_time)) from today t join public.vehicle_runs vr on vr.weekday=t.weekday and vr.active join public.profiles p on p.id=vr.manager_profile_id left join public.vehicle_run_exceptions ve on ve.run_id=vr.id and ve.service_date=t.service_date where coalesce(ve.kind,'changed')<>'cancelled'),'[]'::jsonb)
  ) else null end
$$;

revoke all on function public.staff_save_vehicle_run(uuid,uuid,smallint,time,text,uuid[],text,text,smallint) from public;
revoke all on function public.staff_vehicle_operations() from public;
grant execute on function public.staff_save_vehicle_run(uuid,uuid,smallint,time,text,uuid[],text,text,smallint) to authenticated;
grant execute on function public.staff_vehicle_operations() to authenticated;
