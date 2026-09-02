-- 여러 요일 클래스는 수강 등록 전에 실제 참석 시간을 선택하고,
-- 선택한 시간만 충돌 검사한 뒤 등록과 개인 시간표를 한 트랜잭션으로 저장합니다.

create or replace function public.staff_class_student_schedule_choices(p_class_id uuid,p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수강 요일을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 수강 요일만 설정할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'scheduleId',cs.id,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,
    'assigned',exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id=p_student_id and ssa.class_schedule_id=cs.id)
  ) order by cs.weekday,cs.start_time),'[]'::jsonb) into result
  from public.class_schedules cs
  where cs.class_id=p_class_id
    and (cs.valid_from is null or cs.valid_from<=current_date)
    and (cs.valid_until is null or cs.valid_until>=current_date);
  return result;
end $$;

create or replace function public.prevent_enrollment_student_schedule_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare student_name text; conflict text;
begin
  if new.status<>'active' then return new; end if;
  select s.name into student_name from public.students s where s.id=new.student_id;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict
  from public.class_schedules mine
  join public.enrollments e on e.student_id=new.student_id and e.status='active' and e.class_id<>new.class_id
  join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=mine.weekday
  join public.classes c on c.id=e.class_id and c.active
  where mine.class_id=new.class_id
    and public.student_uses_class_schedule(new.student_id,mine.id)
    and public.student_uses_class_schedule(new.student_id,cs.id)
    and mine.start_time<cs.end_time and mine.end_time>cs.start_time
    and daterange(coalesce(mine.valid_from,'-infinity'::date),coalesce(mine.valid_until,'infinity'::date),'[]')
      && daterange(coalesce(cs.valid_from,'-infinity'::date),coalesce(cs.valid_until,'infinity'::date),'[]')
  order by mine.weekday,mine.start_time limit 1;
  if conflict is not null then raise exception '학생 시간 충돌: % · 기존 % 수업과 겹쳐 클래스를 추가할 수 없습니다.',student_name,conflict; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict
  from public.class_schedules mine
  join public.correction_assignments a on a.student_id=new.student_id and a.active and a.weekday=mine.weekday
  where mine.class_id=new.class_id and public.student_uses_class_schedule(new.student_id,mine.id)
    and mine.start_time<public.correction_time_end(a.end_time,a.slot_index)
    and mine.end_time>public.correction_time_start(a.start_time,a.slot_index)
    and daterange(coalesce(mine.valid_from,'-infinity'::date),coalesce(mine.valid_until,'infinity'::date),'[]')
      && daterange(a.valid_from,coalesce(a.valid_until,'infinity'::date),'[]')
  order by mine.weekday,mine.start_time limit 1;
  if conflict is not null then raise exception '학생 시간 충돌: % · % 고정시간과 겹쳐 클래스를 추가할 수 없습니다.',student_name,conflict; end if;
  return new;
end $$;

create or replace function public.staff_save_class_student_schedule_assignments(p_class_id uuid,p_student_id uuid,p_schedule_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]); prospective uuid[]; keep_enrollment_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수강 요일을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 수강 요일만 설정할 수 있습니다.'; end if;
  if cardinality(requested)=0 then raise exception '최소 한 개의 수업 요일·시간을 선택해 주세요.'; end if;
  if cardinality(requested)<>(select count(distinct id) from unnest(requested) id) then raise exception '중복된 수업 시간이 포함되어 있습니다.'; end if;
  if exists(select 1 from unnest(requested) requested_id where not exists(
    select 1 from public.class_schedules cs where cs.id=requested_id and cs.class_id=p_class_id
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
  )) then raise exception '현재 이 클래스에 등록된 수업 시간만 선택할 수 있습니다.'; end if;

  perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
  select coalesce(array_agg(x.id),'{}'::uuid[]) into prospective from (
    select unnest(requested) id
    union
    select cs.id from public.enrollments e
    join public.classes c on c.id=e.class_id and c.active
    join public.class_schedules cs on cs.class_id=c.id
    where e.student_id=p_student_id and e.status='active' and e.class_id<>p_class_id
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
      and (not exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
        or exists(select 1 from public.student_schedule_assignments where student_id=p_student_id and class_schedule_id=cs.id))
  ) x;
  perform public.assert_student_schedule_selection_available(p_student_id,prospective);

  if not exists(select 1 from public.student_schedule_assignments where student_id=p_student_id) then
    insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
    select p_student_id,cs.id,auth.uid() from public.enrollments e
    join public.classes c on c.id=e.class_id and c.active join public.class_schedules cs on cs.class_id=c.id
    where e.student_id=p_student_id and e.status='active' and e.class_id<>p_class_id
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
    on conflict do nothing;
  end if;
  delete from public.student_schedule_assignments ssa using public.class_schedules cs
  where ssa.class_schedule_id=cs.id and ssa.student_id=p_student_id and cs.class_id=p_class_id;
  insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
  select p_student_id,id,auth.uid() from unnest(requested) id on conflict do nothing;

  select id into keep_enrollment_id from public.enrollments
  where student_id=p_student_id and class_id=p_class_id
  order by (status='active') desc,started_on desc nulls last,id limit 1;
  if keep_enrollment_id is null then
    insert into public.enrollments(student_id,class_id,status,started_on) values(p_student_id,p_class_id,'active',current_date);
  else
    update public.enrollments set status='active',ended_on=null where id=keep_enrollment_id;
    update public.enrollments set status='completed',ended_on=coalesce(ended_on,current_date)
    where student_id=p_student_id and class_id=p_class_id and id<>keep_enrollment_id and status='active';
  end if;
end $$;

create or replace function public.staff_set_class_enrollment(p_class_id uuid,p_student_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
declare all_schedule_ids uuid[];
begin
  if not public.is_staff() then raise exception '교직원만 클래스 학생을 변경할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 학생만 변경할 수 있습니다.'; end if;
  if p_active then
    select coalesce(array_agg(id order by weekday,start_time),'{}'::uuid[]) into all_schedule_ids
    from public.class_schedules where class_id=p_class_id
      and (valid_from is null or valid_from<=current_date) and (valid_until is null or valid_until>=current_date);
    if cardinality(all_schedule_ids)=0 then raise exception '먼저 클래스 수업 시간을 등록해 주세요.'; end if;
    perform public.staff_save_class_student_schedule_assignments(p_class_id,p_student_id,all_schedule_ids);
  else
    update public.enrollments set status='completed',ended_on=current_date
    where student_id=p_student_id and class_id=p_class_id and status='active';
    delete from public.student_schedule_assignments ssa using public.class_schedules cs
    where ssa.student_id=p_student_id and ssa.class_schedule_id=cs.id and cs.class_id=p_class_id;
  end if;
end $$;

revoke all on function public.staff_class_student_schedule_choices(uuid,uuid),public.staff_save_class_student_schedule_assignments(uuid,uuid,uuid[]),public.staff_set_class_enrollment(uuid,uuid,boolean) from public,anon;
grant execute on function public.staff_class_student_schedule_choices(uuid,uuid),public.staff_save_class_student_schedule_assignments(uuid,uuid,uuid[]),public.staff_set_class_enrollment(uuid,uuid,boolean) to authenticated;
revoke all on function public.prevent_enrollment_student_schedule_conflict() from public,anon,authenticated;
notify pgrst,'reload schema';
