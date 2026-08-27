alter table public.learning_report_comments
  alter column lesson_id drop not null,
  add column special_lesson_id uuid references public.teacher_special_lessons(id) on delete cascade;

alter table public.learning_report_comments
  add constraint learning_report_comments_single_target_check
  check (num_nonnulls(lesson_id, special_lesson_id) = 1);

create index learning_report_comments_special_lesson_student_created_idx
  on public.learning_report_comments(special_lesson_id, student_id, created_at)
  where special_lesson_id is not null;

create or replace function public.can_view_family_report(p_student_id uuid,p_lesson_id uuid) returns boolean
language sql stable set search_path=public as $$
  select (
    exists(
      select 1 from public.lessons l
      join public.enrollments e on e.class_id=l.class_id and e.student_id=p_student_id
      where l.id=p_lesson_id and e.started_on<=l.lesson_date
        and (e.ended_on is null or e.ended_on>=l.lesson_date)
    )
    or exists(
      select 1 from public.teacher_special_lessons sl
      join public.teacher_special_lesson_students ss on ss.session_id=sl.id and ss.student_id=p_student_id
      where sl.id=p_lesson_id and sl.status<>'cancelled'
    )
  ) and (
    exists(select 1 from public.students s where s.id=p_student_id and s.profile_id=auth.uid())
    or exists(select 1 from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id
      where g.profile_id=auth.uid() and sg.student_id=p_student_id)
  )
$$;

create or replace function public.can_manage_family_report_comment(p_student_id uuid,p_lesson_id uuid) returns boolean
language sql stable set search_path=public as $$
  select public.current_user_role()='admin'
    or exists(select 1 from public.lessons l where l.id=p_lesson_id and l.teacher_profile_id=auth.uid())
    or exists(
      select 1 from public.teacher_special_lessons sl
      join public.teacher_special_lesson_students ss on ss.session_id=sl.id and ss.student_id=p_student_id
      where sl.id=p_lesson_id and sl.teacher_profile_id=auth.uid()
    )
$$;

create or replace function public.family_report_comments(p_student_id uuid,p_lesson_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_view_family_report(p_student_id,p_lesson_id) then raise exception '확인할 수 없는 리포트입니다.'; end if;
  if public.current_user_role()<>'guardian' then return '[]'::jsonb; end if;
  update public.learning_report_comments set family_read_at=coalesce(family_read_at,now())
    where student_id=p_student_id and coalesce(lesson_id,special_lesson_id)=p_lesson_id and parent_id is not null;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'parentId',c.parent_id,
    'body',case when c.deleted_at is null then c.body else '삭제된 댓글입니다.' end,
    'authorName',p.display_name,'authorRole',p.role,'createdAt',c.created_at,
    'canDelete',c.deleted_at is null and c.author_profile_id=auth.uid() and c.parent_id is null,
    'isDeleted',c.deleted_at is not null
  ) order by c.created_at),'[]'::jsonb) into result
  from public.learning_report_comments c join public.profiles p on p.id=c.author_profile_id
  where c.student_id=p_student_id and coalesce(c.lesson_id,c.special_lesson_id)=p_lesson_id;
  return result;
end $$;

create or replace function public.family_add_report_comment(p_student_id uuid,p_lesson_id uuid,p_body text) returns uuid
language plpgsql security definer set search_path=public as $$
declare new_id uuid; regular_target boolean; special_target boolean;
begin
  if public.current_user_role()<>'guardian' or not public.can_view_family_report(p_student_id,p_lesson_id) then
    raise exception '학부모만 연결된 자녀의 리포트에 댓글을 남길 수 있습니다.';
  end if;
  if char_length(trim(coalesce(p_body,''))) not between 1 and 500 then raise exception '댓글은 1~500자로 입력해 주세요.'; end if;
  select exists(select 1 from public.lessons where id=p_lesson_id),
         exists(select 1 from public.teacher_special_lessons where id=p_lesson_id)
    into regular_target,special_target;
  if regular_target then
    insert into public.learning_report_comments(lesson_id,student_id,author_profile_id,body,family_read_at)
      values(p_lesson_id,p_student_id,auth.uid(),trim(p_body),now()) returning id into new_id;
  elsif special_target then
    insert into public.learning_report_comments(special_lesson_id,student_id,author_profile_id,body,family_read_at)
      values(p_lesson_id,p_student_id,auth.uid(),trim(p_body),now()) returning id into new_id;
  else raise exception '확인할 수 없는 리포트입니다.';
  end if;
  return new_id;
end $$;

create or replace function public.staff_report_comments(p_student_id uuid,p_lesson_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_manage_family_report_comment(p_student_id,p_lesson_id) then raise exception '담당 리포트의 댓글만 확인할 수 있습니다.'; end if;
  update public.learning_report_comments set staff_read_at=coalesce(staff_read_at,now())
    where student_id=p_student_id and coalesce(lesson_id,special_lesson_id)=p_lesson_id and parent_id is null and deleted_at is null;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'parentId',c.parent_id,
    'body',case when c.deleted_at is null then c.body else '삭제된 댓글입니다.' end,
    'authorName',p.display_name,'authorRole',p.role,'createdAt',c.created_at,
    'canDelete',c.deleted_at is null and (public.current_user_role()='admin' or (c.author_profile_id=auth.uid() and c.parent_id is not null)),
    'isDeleted',c.deleted_at is not null
  ) order by c.created_at),'[]'::jsonb) into result
  from public.learning_report_comments c join public.profiles p on p.id=c.author_profile_id
  where c.student_id=p_student_id and coalesce(c.lesson_id,c.special_lesson_id)=p_lesson_id;
  return result;
end $$;

create or replace function public.staff_reply_report_comment(p_comment_id uuid,p_body text) returns uuid
language plpgsql security definer set search_path=public as $$
declare root public.learning_report_comments; new_id uuid;
begin
  select * into root from public.learning_report_comments where id=p_comment_id and parent_id is null;
  if root.id is null or not public.can_manage_family_report_comment(root.student_id,coalesce(root.lesson_id,root.special_lesson_id)) then
    raise exception '답변할 수 없는 댓글입니다.';
  end if;
  if char_length(trim(coalesce(p_body,''))) not between 1 and 500 then raise exception '답변은 1~500자로 입력해 주세요.'; end if;
  insert into public.learning_report_comments(lesson_id,special_lesson_id,student_id,author_profile_id,parent_id,body,staff_read_at)
    values(root.lesson_id,root.special_lesson_id,root.student_id,auth.uid(),root.id,trim(p_body),now()) returning id into new_id;
  update public.learning_report_comments set staff_read_at=coalesce(staff_read_at,now()) where id=root.id;
  return new_id;
end $$;

create or replace function public.delete_report_comment(p_comment_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare target public.learning_report_comments; actor_role text; allowed boolean:=false; root_id uuid;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  select * into target from public.learning_report_comments where id=p_comment_id and deleted_at is null;
  if target.id is null then raise exception '삭제할 댓글을 찾을 수 없습니다.'; end if;
  actor_role:=public.current_user_role();
  if actor_role='admin' then allowed:=true;
  elsif target.author_profile_id=auth.uid() and actor_role='guardian' and target.parent_id is null then
    allowed:=public.can_view_family_report(target.student_id,coalesce(target.lesson_id,target.special_lesson_id));
  elsif target.author_profile_id=auth.uid() and actor_role in ('teacher','manager') and target.parent_id is not null then
    allowed:=public.can_manage_family_report_comment(target.student_id,coalesce(target.lesson_id,target.special_lesson_id));
  end if;
  if not allowed then raise exception '이 댓글을 삭제할 권한이 없습니다.'; end if;
  if target.parent_id is null and exists(select 1 from public.learning_report_comments where parent_id=target.id) then
    update public.learning_report_comments set body='삭제된 댓글입니다.',deleted_at=now() where id=target.id;
  else
    root_id:=target.parent_id;
    delete from public.learning_report_comments where id=target.id;
    if root_id is not null and exists(select 1 from public.learning_report_comments where id=root_id and deleted_at is not null)
      and not exists(select 1 from public.learning_report_comments where parent_id=root_id) then
      delete from public.learning_report_comments where id=root_id;
    end if;
  end if;
end $$;

create or replace function public.report_comment_reactions(p_comment_ids uuid[]) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  with accessible as (
    select c.id from public.learning_report_comments c
    where c.id=any(coalesce(p_comment_ids,array[]::uuid[])) and c.deleted_at is null and (
      (public.current_user_role()='guardian' and public.can_view_family_report(c.student_id,coalesce(c.lesson_id,c.special_lesson_id)))
      or (public.current_user_role() in ('admin','teacher','manager') and public.can_manage_family_report_comment(c.student_id,coalesce(c.lesson_id,c.special_lesson_id)))
    )
  ), grouped as (
    select r.comment_id,r.reaction,count(*)::int total,bool_or(r.profile_id=auth.uid()) selected
    from public.learning_report_comment_reactions r join accessible a on a.id=r.comment_id group by r.comment_id,r.reaction
  )
  select coalesce(jsonb_agg(jsonb_build_object('commentId',a.id,'reactions',coalesce((
    select jsonb_agg(jsonb_build_object('type',g.reaction,'count',g.total,'selected',g.selected) order by g.reaction)
    from grouped g where g.comment_id=a.id),'[]'::jsonb)) order by a.id),'[]'::jsonb) into result from accessible a;
  return result;
end $$;

create or replace function public.toggle_report_comment_reaction(p_comment_id uuid,p_reaction text) returns void
language plpgsql security definer set search_path=public as $$
declare target public.learning_report_comments; existing text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if p_reaction not in ('heart','confirm','done','thanks') then raise exception '지원하지 않는 반응입니다.'; end if;
  select * into target from public.learning_report_comments where id=p_comment_id and deleted_at is null;
  if target.id is null then raise exception '댓글을 찾을 수 없습니다.'; end if;
  if not ((public.current_user_role()='guardian' and public.can_view_family_report(target.student_id,coalesce(target.lesson_id,target.special_lesson_id)))
    or (public.current_user_role() in ('admin','teacher','manager') and public.can_manage_family_report_comment(target.student_id,coalesce(target.lesson_id,target.special_lesson_id)))) then
    raise exception '이 댓글에 반응할 권한이 없습니다.';
  end if;
  select reaction into existing from public.learning_report_comment_reactions where comment_id=p_comment_id and profile_id=auth.uid();
  if existing=p_reaction then delete from public.learning_report_comment_reactions where comment_id=p_comment_id and profile_id=auth.uid();
  else insert into public.learning_report_comment_reactions(comment_id,profile_id,reaction) values(p_comment_id,auth.uid(),p_reaction)
    on conflict(comment_id,profile_id) do update set reaction=excluded.reaction,updated_at=now(); end if;
end $$;

create or replace function public.staff_report_comment_inbox() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if public.current_user_role() not in ('admin','teacher','manager') then raise exception '교직원 댓글함입니다.'; end if;
  with visible as (
    select c.*,coalesce(c.lesson_id,c.special_lesson_id) target_id,
      coalesce(cl.name,case sl.kind when 'makeup' then coalesce(a.name,'')||' 보강' else coalesce(a.name,'')||' 추가수업' end) class_name,
      coalesce(cl.subject,a.main_subject,a.name) subject_name
    from public.learning_report_comments c
    left join public.lessons l on l.id=c.lesson_id
    left join public.classes cl on cl.id=l.class_id
    left join public.teacher_special_lessons sl on sl.id=c.special_lesson_id
    left join public.academy_subjects a on a.id=sl.subject_id
    where c.parent_id is null and (public.current_user_role()='admin' or l.teacher_profile_id=auth.uid() or sl.teacher_profile_id=auth.uid())
    order by c.created_at desc limit 50
  )
  select jsonb_build_object('unreadCount',count(*) filter(where v.staff_read_at is null),'items',coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'lessonId',v.target_id,'studentId',v.student_id,'studentName',s.name,'className',v.class_name,
    'subject',v.subject_name,'body',case when v.deleted_at is null then v.body else '삭제된 댓글입니다.' end,
    'authorName',p.display_name,'readAt',v.staff_read_at,'createdAt',v.created_at) order by v.created_at desc),'[]'::jsonb)) into result
  from visible v join public.students s on s.id=v.student_id join public.profiles p on p.id=v.author_profile_id;
  return result;
end $$;

create or replace function public.family_report_reply_inbox() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if public.current_user_role()<>'guardian' then raise exception '학부모 답변함입니다.'; end if;
  with replies as (
    select reply.*,coalesce(reply.lesson_id,reply.special_lesson_id) target_id,
      coalesce(cl.name,case sl.kind when 'makeup' then coalesce(a.name,'')||' 보강' else coalesce(a.name,'')||' 추가수업' end) class_name,
      coalesce(cl.subject,a.main_subject,a.name) subject_name
    from public.learning_report_comments reply
    join public.learning_report_comments root_comment on root_comment.id=reply.parent_id
    left join public.lessons l on l.id=reply.lesson_id
    left join public.classes cl on cl.id=l.class_id
    left join public.teacher_special_lessons sl on sl.id=reply.special_lesson_id
    left join public.academy_subjects a on a.id=sl.subject_id
    where root_comment.author_profile_id=auth.uid()
    order by reply.created_at desc limit 50
  )
  select jsonb_build_object('unreadCount',count(*) filter(where r.family_read_at is null),'items',coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'lessonId',r.target_id,'studentId',r.student_id,'studentName',s.name,'className',r.class_name,
    'subject',r.subject_name,'body',case when r.deleted_at is null then r.body else '삭제된 댓글입니다.' end,
    'authorName',p.display_name,'readAt',r.family_read_at,'createdAt',r.created_at) order by r.created_at desc),'[]'::jsonb)) into result
  from replies r join public.guardians g on g.profile_id=auth.uid()
  join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=r.student_id
  join public.students s on s.id=r.student_id join public.profiles p on p.id=r.author_profile_id;
  return result;
end $$;
