-- 출결과 보강 변경을 학생·학부모 로그인 계정의 앱 알림으로 전달합니다.

create table public.family_notifications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  event_key text not null,
  title text not null,
  body text not null,
  source_type text not null check(source_type in ('attendance','makeup')),
  source_id uuid not null,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique(recipient_profile_id,event_key,source_type,source_id)
);
create index family_notifications_recipient_idx on public.family_notifications(recipient_profile_id,created_at desc);
alter table public.family_notifications enable row level security;
create policy "recipient_read_family_notifications" on public.family_notifications for select to authenticated using(recipient_profile_id=auth.uid() or public.is_staff());
create policy "recipient_update_family_notifications" on public.family_notifications for update to authenticated using(recipient_profile_id=auth.uid() or public.is_staff()) with check(recipient_profile_id=auth.uid() or public.is_staff());
grant select,update on table public.family_notifications to authenticated;

create or replace function public.enqueue_family_notification(p_student_id uuid,p_event_key text,p_title text,p_body text,p_source_type text,p_source_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  insert into public.family_notifications(student_id,recipient_profile_id,event_key,title,body,source_type,source_id)
  select p_student_id,recipient_id,p_event_key,p_title,p_body,p_source_type,p_source_id from (
    select s.profile_id recipient_id from public.students s where s.id=p_student_id and s.profile_id is not null
    union
    select g.profile_id from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=p_student_id and g.profile_id is not null
  ) recipients
  on conflict(recipient_profile_id,event_key,source_type,source_id) do update set title=excluded.title,body=excluded.body,read_at=null,created_at=now();
end $$;

create or replace function public.notify_attendance_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare class_name text; lesson_day date; label text;
begin
  if tg_op='UPDATE' and old.status=new.status then return new; end if;
  select c.name,l.lesson_date into class_name,lesson_day from public.lessons l join public.classes c on c.id=l.class_id where l.id=new.lesson_id;
  label:=case new.status when 'absent' then '결석' when 'late' then '지각' when 'present' then '출석' else '공결' end;
  perform public.enqueue_family_notification(new.student_id,'status-'||new.status::text,
    case when new.status in ('absent','late') then '출결 알림' else '출결 변경 안내' end,
    to_char(lesson_day,'YYYY.MM.DD')||' '||class_name||' 수업이 '||label||' 처리되었습니다.',
    'attendance',new.id);
  return new;
end $$;
create trigger attendance_notify_family after insert or update of status on public.attendance for each row execute function public.notify_attendance_change();

create or replace function public.notify_makeup_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare student_id uuid; class_name text; title_text text; body_text text;
begin
  if tg_op='UPDATE' and old.status=new.status and old.scheduled_at=new.scheduled_at and old.ends_at=new.ends_at and old.room=new.room then return new; end if;
  select a.student_id,c.name into student_id,class_name from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id where a.id=new.attendance_id;
  title_text:=case new.status when 'scheduled' then '보강 일정 안내' when 'completed' then '보강 완료 안내' else '보강 취소 안내' end;
  body_text:=case new.status when 'scheduled' then class_name||' 보강이 '||to_char(new.scheduled_at at time zone 'Asia/Seoul','MM.DD HH24:MI')||'에 예정되었습니다.' when 'completed' then class_name||' 보강이 완료되었습니다.' else class_name||' 보강 일정이 취소되었습니다.' end;
  perform public.enqueue_family_notification(student_id,'status-'||new.status::text,title_text,body_text,'makeup',new.id);
  return new;
end $$;
create trigger makeup_notify_family after insert or update of status,scheduled_at,ends_at,room on public.makeup_sessions for each row execute function public.notify_makeup_change();

create or replace function public.family_notification_center()
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'unreadCount',count(*) filter(where n.read_at is null),
    'items',coalesce(jsonb_agg(jsonb_build_object('id',n.id,'studentName',s.name,'eventKey',n.event_key,'title',n.title,'body',n.body,'sourceType',n.source_type,'readAt',n.read_at,'createdAt',n.created_at) order by n.created_at desc),'[]'::jsonb)
  ) from (select * from public.family_notifications where recipient_profile_id=auth.uid() order by created_at desc limit 50) n join public.students s on s.id=n.student_id
$$;

create or replace function public.mark_family_notifications_read(p_notification_id uuid default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.family_notifications set read_at=coalesce(read_at,now()) where recipient_profile_id=auth.uid() and (p_notification_id is null or id=p_notification_id);
end $$;
revoke all on function public.family_notification_center() from public;
revoke all on function public.mark_family_notifications_read(uuid) from public;
grant execute on function public.family_notification_center() to authenticated;
grant execute on function public.mark_family_notifications_read(uuid) to authenticated;
