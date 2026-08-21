create or replace function public.consultation_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role;
begin
  v_role:=public.current_user_role();
  if v_role is null then raise exception '로그인이 필요합니다.'; end if;
  return jsonb_build_object(
    'isStaff',public.is_staff(),'isAdmin',v_role='admin',
    'classes',case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'subject',c.subject,'color',c.color,
      'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name)
        from public.enrollments e join public.students s on s.id=e.student_id
        where e.class_id=c.id and e.status='active' and s.status in ('active','재원')),'[]'::jsonb)
    ) order by c.subject,c.name) from public.classes c where c.active and (
      v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid())
    )),'[]'::jsonb) else '[]'::jsonb end,
    'students',case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name)
      from public.students s where s.status in ('active','재원') and (v_role='admin' or exists(
        select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
        where e.student_id=s.id and e.status='active' and ct.profile_id=auth.uid()
      ))),'[]'::jsonb) else '[]'::jsonb end,
    'overdueStudents',case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object(
      'id',target.id,'name',target.name,'lastGuardianConsultedAt',target.last_guardian_consulted_at,
      'daysSinceGuardian',case when target.last_guardian_consulted_at is null then null else floor(extract(epoch from (now()-target.last_guardian_consulted_at))/86400)::integer end
    ) order by target.last_guardian_consulted_at nulls first,target.name) from (
      select s.id,s.name,max(c.consulted_at) filter(where c.consultation_type='guardian') last_guardian_consulted_at
      from public.students s left join public.consultations c on c.student_id=s.id
      where s.status in ('active','재원') and (v_role='admin' or exists(
        select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
        where e.student_id=s.id and e.status='active' and ct.profile_id=auth.uid()
      )) group by s.id,s.name
      having max(c.consulted_at) filter(where c.consultation_type='guardian') is null
        or max(c.consulted_at) filter(where c.consultation_type='guardian')<now()-interval '30 days'
    ) target),'[]'::jsonb) else '[]'::jsonb end,
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'studentId',s.id,'studentName',s.name,'consultantName',coalesce(p.display_name,t.name,'담당 선생님'),
      'consultedAt',c.consulted_at,'consultationType',c.consultation_type,'internalNote',case when public.is_staff() then c.internal_note else null end,
      'guardianSummary',case when public.is_staff() or v_role='guardian' then c.guardian_summary else null end,
      'studentSummary',case when public.is_staff() or v_role='student' then c.student_summary else null end,'nextContactOn',null
    ) order by c.consulted_at desc) from public.consultations c join public.students s on s.id=c.student_id
      left join public.profiles p on p.id=c.consultant_profile_id left join public.teachers t on t.id=c.teacher_id
      where (public.is_staff() and (v_role='admin' or exists(
        select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
        where e.student_id=s.id and e.status='active' and ct.profile_id=auth.uid()
      ))) or (v_role='student' and s.profile_id=auth.uid() and c.student_summary is not null)
      or (v_role='guardian' and c.guardian_summary is not null and exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=s.id and g.profile_id=auth.uid()))
    ),'[]'::jsonb)
  );
end $$;

create or replace function public.staff_save_consultation(
  p_consultation_id uuid,p_student_id uuid,p_consultation_type text,p_consulted_at timestamptz,
  p_internal_note text,p_guardian_summary text,p_student_summary text,p_next_contact_on date
) returns uuid language plpgsql security definer set search_path=public as $$
declare saved_id uuid; v_role public.user_role:=public.current_user_role();
begin
  if not public.is_staff() then raise exception '교직원만 상담 기록을 저장할 수 있습니다.'; end if;
  if p_consultation_type not in ('student','guardian') then raise exception '상담 대상은 학생 또는 학부모를 선택해 주세요.'; end if;
  if not exists(select 1 from public.students s where s.id=p_student_id and s.status in ('active','재원') and (v_role='admin' or exists(
    select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
    where e.student_id=s.id and e.status='active' and ct.profile_id=auth.uid()
  ))) then raise exception '담당 클래스 학생만 상담 기록을 작성할 수 있습니다.'; end if;
  if nullif(trim(p_internal_note),'') is null then raise exception '상담 내용을 입력해 주세요.'; end if;
  if p_consultation_id is null then
    insert into public.consultations(student_id,consultant_profile_id,consulted_at,consultation_type,internal_note,guardian_summary,student_summary,next_contact_on)
    values(p_student_id,auth.uid(),p_consulted_at,p_consultation_type,trim(p_internal_note),null,null,null) returning id into saved_id;
  else
    update public.consultations c set student_id=p_student_id,consultant_profile_id=auth.uid(),consulted_at=p_consulted_at,
      consultation_type=p_consultation_type,internal_note=trim(p_internal_note),guardian_summary=null,student_summary=null,next_contact_on=null
    where c.id=p_consultation_id and (v_role='admin' or exists(
      select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
      where e.student_id=c.student_id and e.status='active' and ct.profile_id=auth.uid()
    )) returning id into saved_id;
    if saved_id is null then raise exception '수정할 수 없는 상담 기록입니다.'; end if;
  end if;
  return saved_id;
end $$;

create or replace function public.staff_delete_consultation(p_consultation_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 상담 기록을 삭제할 수 있습니다.'; end if;
  delete from public.consultations c where c.id=p_consultation_id and (public.current_user_role()='admin' or exists(
    select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id
    where e.student_id=c.student_id and e.status='active' and ct.profile_id=auth.uid()
  ));
  if not found then raise exception '삭제할 수 없는 상담 기록입니다.'; end if;
end $$;

revoke all on function public.consultation_board(),public.staff_save_consultation(uuid,uuid,text,timestamptz,text,text,text,date),public.staff_delete_consultation(uuid) from public,anon;
grant execute on function public.consultation_board(),public.staff_save_consultation(uuid,uuid,text,timestamptz,text,text,text,date),public.staff_delete_consultation(uuid) to authenticated;
notify pgrst,'reload schema';
