-- 한살매 키즈노트: 학생·학부모 공지 확인 여부를 기록하고 교직원이 확인 현황을 봅니다.

create table if not exists public.announcement_read_receipts (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (announcement_id, profile_id)
);
create index if not exists announcement_read_receipts_profile_idx on public.announcement_read_receipts(profile_id, viewed_at desc);
alter table public.announcement_read_receipts enable row level security;

drop policy if exists "own_or_staff_read_announcement_receipts" on public.announcement_read_receipts;
create policy "own_or_staff_read_announcement_receipts" on public.announcement_read_receipts
for select to authenticated using (profile_id=auth.uid() or public.is_staff());

grant select on table public.announcement_read_receipts to authenticated;

create or replace function public.family_announcement_reads()
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('announcementId',announcement_id,'viewedAt',viewed_at) order by viewed_at desc),'[]'::jsonb)
  from public.announcement_read_receipts where profile_id=auth.uid()
$$;

create or replace function public.mark_family_announcement_read(p_announcement_id uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare v_time timestamptz; v_allowed boolean;
begin
  if public.current_user_role() not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 공지를 확인 처리할 수 있습니다.';
  end if;

  select exists(
    select 1 from public.announcements a
    where a.id=p_announcement_id
      and a.published_at is not null and a.published_at<=now()
      and (a.expires_at is null or a.expires_at>now())
      and (
        a.audience='all'
        or (a.audience='class' and (
          exists(select 1 from public.enrollments e join public.students s on s.id=e.student_id where e.class_id=a.class_id and e.status='active' and s.profile_id=auth.uid())
          or exists(select 1 from public.enrollments e join public.student_guardians sg on sg.student_id=e.student_id join public.guardians g on g.id=sg.guardian_id where e.class_id=a.class_id and e.status='active' and g.profile_id=auth.uid())
        ))
        or (a.audience='student' and (
          exists(select 1 from public.students s where s.id=a.student_id and s.profile_id=auth.uid())
          or exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=a.student_id and g.profile_id=auth.uid())
        ))
      )
  ) into v_allowed;
  if not v_allowed then raise exception '확인할 수 없는 공지입니다.'; end if;

  insert into public.announcement_read_receipts(announcement_id,profile_id)
  values(p_announcement_id,auth.uid())
  on conflict(announcement_id,profile_id) do update set viewed_at=coalesce(public.announcement_read_receipts.viewed_at,excluded.viewed_at)
  returning viewed_at into v_time;
  return v_time;
end $$;

create or replace function public.staff_announcement_read_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 공지 확인 현황을 볼 수 있습니다.'; end if;

  with target_profiles as (
    select distinct a.id announcement_id, recipient.profile_id
    from public.announcements a
    join lateral (
      select s.profile_id
      from public.students s
      where s.profile_id is not null and s.status in ('active','재원')
        and (
          a.audience='all'
          or (a.audience='student' and s.id=a.student_id)
          or (a.audience='class' and exists(select 1 from public.enrollments e where e.student_id=s.id and e.class_id=a.class_id and e.status='active'))
        )
      union
      select g.profile_id
      from public.guardians g
      join public.student_guardians sg on sg.guardian_id=g.id
      join public.students s on s.id=sg.student_id
      where g.profile_id is not null and s.status in ('active','재원')
        and (
          a.audience='all'
          or (a.audience='student' and s.id=a.student_id)
          or (a.audience='class' and exists(select 1 from public.enrollments e where e.student_id=s.id and e.class_id=a.class_id and e.status='active'))
        )
    ) recipient on true
    where a.published_at is not null
  ), counts as (
    select a.id,
      count(distinct tp.profile_id)::integer recipient_count,
      count(distinct rr.profile_id)::integer read_count
    from public.announcements a
    left join target_profiles tp on tp.announcement_id=a.id
    left join public.announcement_read_receipts rr on rr.announcement_id=a.id and rr.profile_id=tp.profile_id
    group by a.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'announcementId',a.id,
    'recipientCount',coalesce(c.recipient_count,0),
    'readCount',coalesce(c.read_count,0),
    'unreadCount',greatest(coalesce(c.recipient_count,0)-coalesce(c.read_count,0),0)
  ) order by coalesce(a.published_at,a.created_at) desc),'[]'::jsonb)
  into result
  from public.announcements a left join counts c on c.id=a.id;
  return result;
end $$;

revoke all on function public.family_announcement_reads() from public;
revoke all on function public.mark_family_announcement_read(uuid) from public;
revoke all on function public.staff_announcement_read_overview() from public;
grant execute on function public.family_announcement_reads() to authenticated;
grant execute on function public.mark_family_announcement_read(uuid) to authenticated;
grant execute on function public.staff_announcement_read_overview() to authenticated;

notify pgrst,'reload schema';
