-- 대상별 공지 공개와 외부 문자업체 연결 전 안전한 발송 대기열을 추가합니다.

alter table public.announcements
  add column student_id uuid references public.students(id) on delete cascade,
  add column expires_at timestamptz;

alter table public.message_logs
  add column recipient_name text,
  add column announcement_id uuid references public.announcements(id) on delete set null;

grant select, insert, update, delete on table public.announcements, public.message_logs to authenticated;

drop policy if exists "authenticated_read_published_announcements" on public.announcements;
create policy "targeted_read_published_announcements" on public.announcements for select to authenticated using (
  public.is_staff() or (
    published_at is not null and published_at <= now() and (expires_at is null or expires_at > now()) and (
      audience = 'all'
      or (audience = 'class' and (
        exists (
          select 1 from public.enrollments e join public.students s on s.id = e.student_id
          where e.class_id = announcements.class_id and e.status = 'active' and s.profile_id = auth.uid()
        ) or exists (
          select 1 from public.enrollments e
          join public.student_guardians sg on sg.student_id = e.student_id
          join public.guardians g on g.id = sg.guardian_id
          where e.class_id = announcements.class_id and e.status = 'active' and g.profile_id = auth.uid()
        )
      ))
      or (audience = 'student' and (
        exists (select 1 from public.students s where s.id = announcements.student_id and s.profile_id = auth.uid())
        or exists (
          select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
          where sg.student_id = announcements.student_id and g.profile_id = auth.uid()
        )
      ))
    )
  )
);

create or replace function public.communication_board()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'isStaff', public.is_staff(),
    'classes', case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name) from public.classes c where c.active), '[]'::jsonb) else '[]'::jsonb end,
    'students', case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name) from public.students s where s.status in ('active', '재원')), '[]'::jsonb) else '[]'::jsonb end,
    'announcements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'title', a.title,
        'body', a.body,
        'audience', a.audience,
        'classId', a.class_id,
        'className', c.name,
        'studentId', a.student_id,
        'studentName', s.name,
        'authorName', coalesce(p.display_name, '한살매'),
        'publishedAt', a.published_at,
        'expiresAt', a.expires_at,
        'createdAt', a.created_at
      ) order by coalesce(a.published_at, a.created_at) desc)
      from public.announcements a
      left join public.classes c on c.id = a.class_id
      left join public.students s on s.id = a.student_id
      left join public.profiles p on p.id = a.author_profile_id
      where public.is_staff() or (
        a.published_at is not null and a.published_at <= now() and (a.expires_at is null or a.expires_at > now()) and (
          a.audience = 'all'
          or (a.audience = 'class' and exists (
            select 1 from public.enrollments e join public.students target on target.id = e.student_id
            where e.class_id = a.class_id and e.status = 'active' and (
              target.profile_id = auth.uid() or exists (
                select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
                where sg.student_id = target.id and g.profile_id = auth.uid()
              )
            )
          ))
          or (a.audience = 'student' and (
            s.profile_id = auth.uid() or exists (
              select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
              where sg.student_id = s.id and g.profile_id = auth.uid()
            )
          ))
        )
      )
    ), '[]'::jsonb),
    'messageLogs', case when public.is_staff() then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ml.id,
        'studentName', s.name,
        'recipientName', coalesce(ml.recipient_name, s.name),
        'recipientPhone', left(ml.recipient_phone, 3) || '-****-' || right(ml.recipient_phone, 4),
        'body', ml.body,
        'status', ml.status,
        'errorMessage', ml.error_message,
        'sentAt', ml.sent_at,
        'createdAt', ml.created_at
      ) order by ml.created_at desc)
      from (select * from public.message_logs order by created_at desc limit 100) ml
      left join public.students s on s.id = ml.student_id
    ), '[]'::jsonb) else '[]'::jsonb end
  )
$$;

create or replace function public.staff_save_announcement(
  p_announcement_id uuid,
  p_title text,
  p_body text,
  p_audience text,
  p_target_id uuid,
  p_published_at timestamptz,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare saved_id uuid; target_class uuid; target_student uuid;
begin
  if not public.is_staff() then raise exception '교직원만 공지를 저장할 수 있습니다.'; end if;
  if nullif(trim(p_title), '') is null or nullif(trim(p_body), '') is null then raise exception '공지 제목과 내용을 입력해 주세요.'; end if;
  if p_audience not in ('all', 'class', 'student') then raise exception '공지 대상을 선택해 주세요.'; end if;
  if p_audience = 'class' and not exists (select 1 from public.classes c where c.id = p_target_id and c.active) then raise exception '클래스를 선택해 주세요.'; end if;
  if p_audience = 'student' and not exists (select 1 from public.students s where s.id = p_target_id) then raise exception '학생을 선택해 주세요.'; end if;
  if p_expires_at is not null and p_published_at is not null and p_expires_at <= p_published_at then raise exception '공개 종료는 게시 시간보다 늦어야 합니다.'; end if;
  target_class := case when p_audience = 'class' then p_target_id else null end;
  target_student := case when p_audience = 'student' then p_target_id else null end;

  if p_announcement_id is null then
    insert into public.announcements(class_id, student_id, author_profile_id, title, body, audience, published_at, expires_at)
    values (target_class, target_student, auth.uid(), trim(p_title), trim(p_body), p_audience, p_published_at, p_expires_at)
    returning id into saved_id;
  else
    update public.announcements set class_id = target_class, student_id = target_student, author_profile_id = auth.uid(), title = trim(p_title), body = trim(p_body), audience = p_audience, published_at = p_published_at, expires_at = p_expires_at
    where id = p_announcement_id returning id into saved_id;
    if saved_id is null then raise exception '공지를 찾을 수 없습니다.'; end if;
  end if;
  return saved_id;
end
$$;

create or replace function public.staff_delete_announcement(p_announcement_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception '교직원만 공지를 삭제할 수 있습니다.'; end if;
  delete from public.announcements where id = p_announcement_id;
  if not found then raise exception '공지를 찾을 수 없습니다.'; end if;
end
$$;

create or replace function public.staff_message_recipient_preview(p_target_type text, p_target_id uuid, p_recipient_kind text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with target_students as (
    select distinct s.id, s.name, s.phone
    from public.students s
    where s.status in ('active', '재원') and (
      p_target_type = 'all'
      or (p_target_type = 'student' and s.id = p_target_id)
      or (p_target_type = 'class' and exists (select 1 from public.enrollments e where e.student_id = s.id and e.class_id = p_target_id and e.status = 'active'))
    )
  ), recipients as (
    select ts.id as student_id, ts.name as student_name, ts.name as recipient_name, ts.phone, 'student'::text as kind
    from target_students ts where p_recipient_kind in ('student', 'both') and nullif(trim(ts.phone), '') is not null
    union all
    select ts.id, ts.name, g.name, g.phone, 'guardian'::text
    from target_students ts join public.student_guardians sg on sg.student_id = ts.id join public.guardians g on g.id = sg.guardian_id
    where p_recipient_kind in ('guardian', 'both') and nullif(trim(g.phone), '') is not null
  )
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object(
    'studentId', student_id,
    'studentName', student_name,
    'recipientName', recipient_name,
    'phone', left(phone, 3) || '-****-' || right(phone, 4),
    'kind', kind
  ) order by student_name, kind), '[]'::jsonb) else '[]'::jsonb end from recipients
$$;

create or replace function public.staff_queue_messages(p_target_type text, p_target_id uuid, p_recipient_kind text, p_body text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare queued_count integer;
begin
  if not public.is_staff() then raise exception '교직원만 문자를 발송 대기열에 등록할 수 있습니다.'; end if;
  if p_target_type not in ('all', 'class', 'student') then raise exception '문자 대상을 선택해 주세요.'; end if;
  if p_recipient_kind not in ('student', 'guardian', 'both') then raise exception '수신자 유형을 선택해 주세요.'; end if;
  if nullif(trim(p_body), '') is null then raise exception '문자 내용을 입력해 주세요.'; end if;

  with target_students as (
    select distinct s.id, s.name, s.phone from public.students s
    where s.status in ('active', '재원') and (
      p_target_type = 'all' or (p_target_type = 'student' and s.id = p_target_id)
      or (p_target_type = 'class' and exists (select 1 from public.enrollments e where e.student_id = s.id and e.class_id = p_target_id and e.status = 'active'))
    )
  ), recipients as (
    select ts.id as student_id, ts.name as recipient_name, ts.phone from target_students ts where p_recipient_kind in ('student', 'both') and nullif(trim(ts.phone), '') is not null
    union all
    select ts.id, g.name, g.phone from target_students ts join public.student_guardians sg on sg.student_id = ts.id join public.guardians g on g.id = sg.guardian_id
    where p_recipient_kind in ('guardian', 'both') and nullif(trim(g.phone), '') is not null
  )
  insert into public.message_logs(student_id, recipient_name, recipient_phone, message_type, body, provider, status)
  select student_id, recipient_name, phone, 'manual', trim(p_body), 'pending', 'queued' from recipients;
  get diagnostics queued_count = row_count;
  return queued_count;
end
$$;

revoke all on function public.communication_board() from public;
revoke all on function public.staff_save_announcement(uuid, text, text, text, uuid, timestamptz, timestamptz) from public;
revoke all on function public.staff_delete_announcement(uuid) from public;
revoke all on function public.staff_message_recipient_preview(text, uuid, text) from public;
revoke all on function public.staff_queue_messages(text, uuid, text, text) from public;
grant execute on function public.communication_board() to authenticated;
grant execute on function public.staff_save_announcement(uuid, text, text, text, uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.staff_delete_announcement(uuid) to authenticated;
grant execute on function public.staff_message_recipient_preview(text, uuid, text) to authenticated;
grant execute on function public.staff_queue_messages(text, uuid, text, text) to authenticated;
