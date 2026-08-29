-- Keep correction feed publications in the existing family notification center.
-- The existing unique key in family_notifications prevents duplicate inbox rows.

create or replace function public.notify_family_correction_report_published()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.published is true and (tg_op='INSERT' or old.published is distinct from true) then
    perform public.enqueue_family_notification(
      new.student_id,
      'correction-report',
      '새 첨삭 기록이 등록됐어요',
      to_char(new.correction_date,'MM.DD')||' '||coalesce(new.subject,'')||' 첨삭 기록을 확인해 주세요.',
      'learning_report',
      new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists correction_report_notify_family on public.correction_reports;
create trigger correction_report_notify_family
after insert or update of published on public.correction_reports
for each row execute function public.notify_family_correction_report_published();

revoke all on function public.notify_family_correction_report_published() from public,anon,authenticated;

-- Recover today's already-published correction feeds that predate this trigger.
do $$
declare report record;
begin
  for report in
    select id,student_id,correction_date,subject
    from public.correction_reports
    where published is true
      and correction_date=(now() at time zone 'Asia/Seoul')::date
  loop
    perform public.enqueue_family_notification(
      report.student_id,
      'correction-report',
      '새 첨삭 기록이 등록됐어요',
      to_char(report.correction_date,'MM.DD')||' '||coalesce(report.subject,'')||' 첨삭 기록을 확인해 주세요.',
      'learning_report',
      report.id
    );
  end loop;
end;
$$;

notify pgrst,'reload schema';
