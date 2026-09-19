CREATE OR REPLACE FUNCTION public.staff_update_class_with_teachers(p_class_id uuid, p_name text, p_subject_id uuid, p_room text, p_color text, p_schedules jsonb, p_teacher_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  schedule_row jsonb;
  normalized_teacher_ids uuid[];
  blocked_students text;
  subject_row public.academy_subjects%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
  perform 1 from public.classes where id=p_class_id for update;
  if not public.is_staff()
     or (public.current_user_role()<>'admin' and not exists(
       select 1 from public.class_teachers ct
       where ct.class_id=p_class_id and ct.profile_id=auth.uid()
     )) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '클래스 이름을 입력해 주세요.'; end if;

  select coalesce(array_agg(distinct selected.teacher_id order by selected.teacher_id),'{}'::uuid[])
  into normalized_teacher_ids
  from unnest(coalesce(p_teacher_ids,'{}'::uuid[])) selected(teacher_id);

  if coalesce(array_length(normalized_teacher_ids,1),0)=0 and public.current_user_role()<>'admin' then
    raise exception '담당 선생님을 한 명 이상 선택해 주세요.';
  end if;
  if public.current_user_role()<>'admin' and not auth.uid()=any(normalized_teacher_ids) then
    raise exception '본인을 담당 선생님에서 제외할 수 없습니다.';
  end if;
  if exists(
    select 1 from unnest(normalized_teacher_ids) selected(id)
    left join public.profiles p on p.id=selected.id
    where p.id is null or p.role not in ('admin','teacher','sub_admin','manager') or not p.is_active
  ) then raise exception '선택한 담당 선생님 계정을 확인해 주세요.'; end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception '수업 요일과 시간을 입력해 주세요.';
  end if;

  select s.* into subject_row from public.academy_subjects s
  where s.id=p_subject_id and s.active limit 1;
  if subject_row.id is null then raise exception '사용 가능한 과목을 선택해 주세요.'; end if;
  if exists(
    select 1 from public.classes c
    where c.id<>p_class_id and c.active
      and lower(regexp_replace(c.name,'\s+','','g'))=lower(regexp_replace(trim(p_name),'\s+','','g'))
  ) then raise exception '같은 이름의 클래스가 이미 있습니다.'; end if;

  update public.classes c set
    name=trim(p_name), subject=subject_row.name, subject_id=subject_row.id,
    room=nullif(trim(p_room),''), color=coalesce(nullif(trim(p_color),''),'#922D61')
  where c.id=p_class_id;
  if not found then raise exception '클래스를 찾을 수 없습니다.'; end if;

  delete from public.class_teachers ct where ct.class_id=p_class_id;

  -- Preserve identity for an unambiguous same-weekday time edit.
  -- Exact matches are excluded first; ambiguous splits/merges keep the guard.
  with requested as (
    select distinct (x->>'weekday')::smallint weekday,
      (x->>'startTime')::time start_time,(x->>'endTime')::time end_time
    from jsonb_array_elements(p_schedules) x
  ), old_unmatched as (
    select cs.*,count(*) over(partition by cs.weekday) day_count
    from public.class_schedules cs
    where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date)
      and not exists(select 1 from requested r where r.weekday=cs.weekday and r.start_time=cs.start_time and r.end_time=cs.end_time)
  ), new_unmatched as (
    select r.*,count(*) over(partition by r.weekday) day_count
    from requested r
    where not exists(select 1 from public.class_schedules cs where cs.class_id=p_class_id
      and (cs.valid_until is null or cs.valid_until>=current_date)
      and cs.weekday=r.weekday and cs.start_time=r.start_time and cs.end_time=r.end_time)
  )
  update public.class_schedules cs set start_time=n.start_time,end_time=n.end_time
  from old_unmatched o join new_unmatched n on n.weekday=o.weekday
  where cs.id=o.id and o.day_count=1 and n.day_count=1;

  select string_agg(detail,', ' order by detail) into blocked_students
  from (
    select distinct st.name||' ('||(array['월','화','수','목','금','토','일'])[cs.weekday]||' '||
      to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')||')' detail
    from public.student_schedule_assignments ssa
    join public.students st on st.id=ssa.student_id
    join public.class_schedules cs on cs.id=ssa.class_schedule_id
    where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date)
      and not exists(select 1 from jsonb_array_elements(p_schedules) x
        where (x->>'weekday')::int=cs.weekday and (x->>'startTime')::time=cs.start_time and (x->>'endTime')::time=cs.end_time)
  ) affected;
  if blocked_students is not null then
    raise exception '개별 수강요일 확인: %. 배정된 요일을 삭제하거나 여러 시간으로 바꾸려면 학생의 수강요일을 먼저 조정해 주세요.',blocked_students;
  end if;

  delete from public.class_schedules cs where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date) and not exists(select 1 from jsonb_array_elements(p_schedules) x where (x->>'weekday')::int=cs.weekday and (x->>'startTime')::time=cs.start_time and (x->>'endTime')::time=cs.end_time);

  for schedule_row in select value from jsonb_array_elements(p_schedules)
  loop
    if (schedule_row->>'weekday')::smallint not between 1 and 7 then
      raise exception '수업 요일을 확인해 주세요.';
    end if;
    if (schedule_row->>'startTime')::time >= (schedule_row->>'endTime')::time then
      raise exception '종료 시간은 시작 시간보다 늦어야 합니다.';
    end if;
    if not exists(select 1 from public.class_schedules cs where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date) and cs.weekday=(schedule_row->>'weekday')::int and cs.start_time=(schedule_row->>'startTime')::time and cs.end_time=(schedule_row->>'endTime')::time) then
    insert into public.class_schedules(class_id,weekday,start_time,end_time)
    values(
      p_class_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time
    );
    end if;
  end loop;

  -- Validate the final teacher roster against the final schedule.
  insert into public.class_teachers(class_id,profile_id)
  select p_class_id,id from unnest(normalized_teacher_ids) selected(id);

end
$function$
;
