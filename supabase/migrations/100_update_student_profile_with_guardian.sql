create or replace function public.staff_update_student_profile_with_guardian(
  p_student_id uuid,p_name text,p_school text,p_grade text,p_phone text,p_residence text,
  p_pickup_location text,p_dropoff_location text,p_status text,p_internal_note text,
  p_guardian_name text,p_guardian_phone text
) returns jsonb language plpgsql security invoker set search_path=public as $$
declare
  saved public.students;
  guardian_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 학생 정보를 수정할 수 있습니다.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '학생 이름을 입력해 주세요.'; end if;

  update public.students set
    name=trim(p_name),school=nullif(trim(p_school),''),grade=nullif(trim(p_grade),''),
    phone=nullif(trim(p_phone),''),residence=nullif(trim(p_residence),''),
    vehicle_pickup_location=nullif(trim(p_pickup_location),''),vehicle_dropoff_location=nullif(trim(p_dropoff_location),''),
    status=p_status,internal_note=nullif(trim(p_internal_note),'')
  where id=p_student_id returning * into saved;
  if saved.id is null then raise exception '학생을 찾을 수 없습니다.'; end if;

  select sg.guardian_id into guardian_id from public.student_guardians sg
  where sg.student_id=p_student_id order by sg.is_primary desc limit 1;
  if guardian_id is not null then
    if nullif(trim(p_guardian_phone),'') is null then raise exception '학부모 연락처를 입력해 주세요.'; end if;
    update public.guardians set name=coalesce(nullif(trim(p_guardian_name),''),saved.name||' 보호자'),phone=trim(p_guardian_phone) where id=guardian_id;
  elsif nullif(trim(p_guardian_phone),'') is not null then
    insert into public.guardians(name,phone) values(coalesce(nullif(trim(p_guardian_name),''),saved.name||' 보호자'),trim(p_guardian_phone)) returning id into guardian_id;
    insert into public.student_guardians(student_id,guardian_id,relationship,is_primary) values(p_student_id,guardian_id,'학부모',true);
  end if;

  return jsonb_build_object('id',saved.id,'name',saved.name,'school',saved.school,'grade',saved.grade,'status',saved.status);
end $$;
revoke all on function public.staff_update_student_profile_with_guardian(uuid,text,text,text,text,text,text,text,text,text,text,text) from public;
grant execute on function public.staff_update_student_profile_with_guardian(uuid,text,text,text,text,text,text,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
