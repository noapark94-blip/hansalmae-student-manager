-- 한살매 키즈노트 1차 마감: 수업 리포트가 작성/수정되면 학생·학부모 앱 알림센터에 안내합니다.

alter table public.family_notifications drop constraint if exists family_notifications_source_type_check;
alter table public.family_notifications add constraint family_notifications_source_type_check
  check (source_type in ('attendance','makeup','tuition','learning_report'));

create or replace function public.enqueue_learning_report_notification(p_lesson_id uuid, p_student_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_name text;
  v_subject text;
  v_lesson_date date;
  v_student record;
begin
  select c.name, c.subject, l.lesson_date
    into v_class_name, v_subject, v_lesson_date
  from public.lessons l
  join public.classes c on c.id = l.class_id
  where l.id = p_lesson_id;

  if v_class_name is null then return; end if;

  for v_student in
    select distinct s.id
    from public.lessons l
    join public.enrollments e on e.class_id = l.class_id
    join public.students s on s.id = e.student_id
    where l.id = p_lesson_id
      and e.started_on <= l.lesson_date
      and (e.ended_on is null or e.ended_on >= l.lesson_date)
      and (p_student_id is null or s.id = p_student_id)
  loop
    perform public.enqueue_family_notification(
      v_student.id,
      'learning-report',
      '새 학습 리포트',
      to_char(v_lesson_date,'MM.DD') || ' ' || coalesce(v_subject,'') || ' ' || v_class_name || ' 수업 기록이 업데이트되었습니다.',
      'learning_report',
      p_lesson_id
    );
  end loop;
end;
$$;

create or replace function public.notify_learning_report_from_lesson()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op='UPDATE' and
     coalesce(old.lesson_content,'') = coalesce(new.lesson_content,'') and
     coalesce(old.homework_content,'') = coalesce(new.homework_content,'') and
     coalesce(old.exam_content,'') = coalesce(new.exam_content,'') then
    return new;
  end if;
  if nullif(trim(coalesce(new.lesson_content,'')),'') is not null
     or nullif(trim(coalesce(new.homework_content,'')),'') is not null
     or nullif(trim(coalesce(new.exam_content,'')),'') is not null then
    perform public.enqueue_learning_report_notification(new.id, null);
  end if;
  return new;
end;
$$;

drop trigger if exists lesson_notify_family_report on public.lessons;
create trigger lesson_notify_family_report
after insert or update of lesson_content, homework_content, exam_content on public.lessons
for each row execute function public.notify_learning_report_from_lesson();

create or replace function public.notify_learning_report_from_exam()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_learning_report_notification(new.lesson_id, new.student_id);
  return new;
end;
$$;

drop trigger if exists lesson_exam_notify_family_report on public.lesson_exam_results;
create trigger lesson_exam_notify_family_report
after insert or update on public.lesson_exam_results
for each row execute function public.notify_learning_report_from_exam();

create or replace function public.notify_learning_report_from_homework()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.enqueue_learning_report_notification(new.lesson_id, new.student_id);
  return new;
end;
$$;

drop trigger if exists lesson_homework_notify_family_report on public.lesson_homework_results;
create trigger lesson_homework_notify_family_report
after insert or update on public.lesson_homework_results
for each row execute function public.notify_learning_report_from_homework();

create or replace function public.family_notification_center()
returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'unreadCount',count(*) filter(where n.read_at is null),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',n.id,'studentName',s.name,'eventKey',n.event_key,'title',n.title,'body',n.body,
      'sourceType',n.source_type,'sourceId',n.source_id,'readAt',n.read_at,'createdAt',n.created_at
    ) order by n.created_at desc),'[]'::jsonb)
  )
  from (select * from public.family_notifications where recipient_profile_id=auth.uid() order by created_at desc limit 50) n
  join public.students s on s.id=n.student_id
$$;

notify pgrst, 'reload schema';
