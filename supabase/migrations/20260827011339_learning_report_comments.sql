-- 학부모 학습 피드 댓글과 담당 선생님 답변함
create table public.learning_report_comments (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  author_profile_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid references public.learning_report_comments(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 500),
  staff_read_at timestamptz,
  family_read_at timestamptz,
  created_at timestamptz not null default now(),
  check (parent_id is null or parent_id <> id)
);

create index learning_report_comments_thread_idx on public.learning_report_comments(lesson_id,student_id,created_at);
create index learning_report_comments_staff_unread_idx on public.learning_report_comments(staff_read_at,created_at desc) where parent_id is null;
create index learning_report_comments_family_unread_idx on public.learning_report_comments(author_profile_id,family_read_at,created_at desc) where parent_id is not null;
alter table public.learning_report_comments enable row level security;
revoke all on table public.learning_report_comments from public, anon, authenticated;

create or replace function public.family_can_report_comment()
returns boolean language sql stable security invoker set search_path=public as $$ select public.current_user_role()='guardian' $$;

create or replace function public.can_view_family_report(p_student_id uuid,p_lesson_id uuid)
returns boolean language sql stable security invoker set search_path=public as $$
  select exists(
    select 1 from public.lessons l
    join public.enrollments e on e.class_id=l.class_id and e.student_id=p_student_id
    where l.id=p_lesson_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)
  ) and (
    exists(select 1 from public.students s where s.id=p_student_id and s.profile_id=auth.uid())
    or exists(select 1 from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id where g.profile_id=auth.uid() and sg.student_id=p_student_id)
  )
$$;

create or replace function public.can_manage_family_report_comment(p_student_id uuid,p_lesson_id uuid)
returns boolean language sql stable security invoker set search_path=public as $$
  select public.current_user_role()='admin' or exists(
    select 1 from public.lessons l where l.id=p_lesson_id and l.teacher_profile_id=auth.uid()
  )
$$;

create or replace function public.family_report_comments(p_student_id uuid,p_lesson_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_view_family_report(p_student_id,p_lesson_id) then raise exception '확인할 수 없는 리포트입니다.'; end if;
  if public.current_user_role()<>'guardian' then return '[]'::jsonb; end if;
  update public.learning_report_comments set family_read_at=coalesce(family_read_at,now())
    where student_id=p_student_id and lesson_id=p_lesson_id and parent_id is not null;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'parentId',c.parent_id,'body',c.body,'authorName',p.display_name,'authorRole',p.role,'createdAt',c.created_at) order by c.created_at),'[]'::jsonb)
    into result from public.learning_report_comments c join public.profiles p on p.id=c.author_profile_id
    where c.student_id=p_student_id and c.lesson_id=p_lesson_id;
  return result;
end $$;

create or replace function public.family_add_report_comment(p_student_id uuid,p_lesson_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=public as $$
declare new_id uuid;
begin
  if public.current_user_role()<>'guardian' or not public.can_view_family_report(p_student_id,p_lesson_id) then raise exception '학부모만 연결된 자녀의 리포트에 댓글을 남길 수 있습니다.'; end if;
  if char_length(trim(coalesce(p_body,''))) not between 1 and 500 then raise exception '댓글은 1~500자로 입력해 주세요.'; end if;
  insert into public.learning_report_comments(lesson_id,student_id,author_profile_id,body,family_read_at)
    values(p_lesson_id,p_student_id,auth.uid(),trim(p_body),now()) returning id into new_id;
  return new_id;
end $$;

create or replace function public.staff_report_comment_inbox()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if public.current_user_role() not in ('admin','teacher','manager') then raise exception '교직원 댓글함입니다.'; end if;
  select jsonb_build_object(
    'unreadCount',count(*) filter(where c.staff_read_at is null),
    'items',coalesce(jsonb_agg(jsonb_build_object('id',c.id,'lessonId',c.lesson_id,'studentId',c.student_id,'studentName',s.name,'className',cl.name,'subject',cl.subject,'body',c.body,'authorName',p.display_name,'readAt',c.staff_read_at,'createdAt',c.created_at) order by c.created_at desc),'[]'::jsonb)
  ) into result
  from (select c.* from public.learning_report_comments c join public.lessons l on l.id=c.lesson_id where c.parent_id is null and (public.current_user_role()='admin' or l.teacher_profile_id=auth.uid()) order by c.created_at desc limit 50) c
  join public.students s on s.id=c.student_id join public.lessons l on l.id=c.lesson_id join public.classes cl on cl.id=l.class_id join public.profiles p on p.id=c.author_profile_id;
  return result;
end $$;

create or replace function public.family_report_reply_inbox()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if public.current_user_role()<>'guardian' then raise exception '학부모 답변함입니다.'; end if;
  select jsonb_build_object(
    'unreadCount',count(*) filter(where c.family_read_at is null),
    'items',coalesce(jsonb_agg(jsonb_build_object('id',c.id,'lessonId',c.lesson_id,'studentId',c.student_id,'studentName',s.name,'className',cl.name,'subject',cl.subject,'body',c.body,'authorName',p.display_name,'readAt',c.family_read_at,'createdAt',c.created_at) order by c.created_at desc),'[]'::jsonb)
  ) into result
  from (select reply.* from public.learning_report_comments reply
    join public.learning_report_comments root_comment on root_comment.id=reply.parent_id
    where root_comment.author_profile_id=auth.uid() order by reply.created_at desc limit 50) c
  join public.guardians g on g.profile_id=auth.uid() join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=c.student_id
  join public.students s on s.id=c.student_id join public.lessons l on l.id=c.lesson_id join public.classes cl on cl.id=l.class_id join public.profiles p on p.id=c.author_profile_id
  ;
  return result;
end $$;

create or replace function public.staff_report_comments(p_student_id uuid,p_lesson_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.can_manage_family_report_comment(p_student_id,p_lesson_id) then raise exception '담당 리포트의 댓글만 확인할 수 있습니다.'; end if;
  update public.learning_report_comments set staff_read_at=coalesce(staff_read_at,now()) where student_id=p_student_id and lesson_id=p_lesson_id and parent_id is null;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'parentId',c.parent_id,'body',c.body,'authorName',p.display_name,'authorRole',p.role,'createdAt',c.created_at) order by c.created_at),'[]'::jsonb)
    into result from public.learning_report_comments c join public.profiles p on p.id=c.author_profile_id where c.student_id=p_student_id and c.lesson_id=p_lesson_id;
  return result;
end $$;

create or replace function public.staff_reply_report_comment(p_comment_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path=public as $$
declare root public.learning_report_comments; new_id uuid;
begin
  select * into root from public.learning_report_comments where id=p_comment_id and parent_id is null;
  if root.id is null or not public.can_manage_family_report_comment(root.student_id,root.lesson_id) then raise exception '답변할 수 없는 댓글입니다.'; end if;
  if char_length(trim(coalesce(p_body,''))) not between 1 and 500 then raise exception '답변은 1~500자로 입력해 주세요.'; end if;
  insert into public.learning_report_comments(lesson_id,student_id,author_profile_id,parent_id,body,staff_read_at)
    values(root.lesson_id,root.student_id,auth.uid(),root.id,trim(p_body),now()) returning id into new_id;
  update public.learning_report_comments set staff_read_at=coalesce(staff_read_at,now()) where id=root.id;
  return new_id;
end $$;

revoke all on function public.family_can_report_comment(),public.can_view_family_report(uuid,uuid),public.can_manage_family_report_comment(uuid,uuid),public.family_report_comments(uuid,uuid),public.family_add_report_comment(uuid,uuid,text),public.staff_report_comment_inbox(),public.family_report_reply_inbox(),public.staff_report_comments(uuid,uuid),public.staff_reply_report_comment(uuid,text) from public,anon;
grant execute on function public.family_can_report_comment(),public.can_view_family_report(uuid,uuid),public.can_manage_family_report_comment(uuid,uuid),public.family_report_comments(uuid,uuid),public.family_add_report_comment(uuid,uuid,text),public.staff_report_comment_inbox(),public.family_report_reply_inbox(),public.staff_report_comments(uuid,uuid),public.staff_reply_report_comment(uuid,text) to authenticated;
notify pgrst,'reload schema';
