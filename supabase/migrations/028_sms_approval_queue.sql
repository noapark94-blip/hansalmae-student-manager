-- 앱 알림에서 학부모 문자 초안을 만들고 관리자 승인 후 발송 준비 상태로 전환합니다.

alter table public.message_logs
  add column source_notification_id uuid unique references public.family_notifications(id) on delete set null,
  add column approved_by uuid references public.profiles(id) on delete set null,
  add column approved_at timestamptz,
  add column cancelled_at timestamptz;

alter table public.message_logs alter column status set default 'pending_approval';
update public.message_logs set status='pending_approval' where status='queued';

create or replace function public.normalize_message_approval_status()
returns trigger language plpgsql as $$
begin
  if new.status='queued' then new.status:='pending_approval'; end if;
  return new;
end $$;
create trigger message_normalize_approval before insert or update of status on public.message_logs for each row execute function public.normalize_message_approval_status();

create or replace function public.create_guardian_message_draft()
returns trigger language plpgsql security definer set search_path=public as $$
declare guardian_name text; guardian_phone text; student_name text;
begin
  select s.name into student_name from public.students s where s.id=new.student_id;
  select g.name,g.phone into guardian_name,guardian_phone from public.guardians g where g.profile_id=new.recipient_profile_id and nullif(trim(g.phone),'') is not null;
  if guardian_phone is not null then
    insert into public.message_logs(student_id,recipient_name,recipient_phone,message_type,body,provider,status,source_notification_id)
    values(new.student_id,guardian_name,guardian_phone,new.source_type,'[한살매] '||student_name||' 학생 · '||new.body,'pending','pending_approval',new.id)
    on conflict(source_notification_id) do update set recipient_name=excluded.recipient_name,recipient_phone=excluded.recipient_phone,body=excluded.body,status=case when public.message_logs.status in ('sent','approved') then public.message_logs.status else 'pending_approval' end,error_message=null;
  end if;
  return new;
end $$;
create trigger family_notification_create_message after insert or update of title,body on public.family_notifications for each row execute function public.create_guardian_message_draft();

insert into public.message_logs(student_id,recipient_name,recipient_phone,message_type,body,provider,status,source_notification_id)
select n.student_id,g.name,g.phone,n.source_type,'[한살매] '||s.name||' 학생 · '||n.body,'pending','pending_approval',n.id
from public.family_notifications n join public.guardians g on g.profile_id=n.recipient_profile_id join public.students s on s.id=n.student_id
where nullif(trim(g.phone),'') is not null
on conflict(source_notification_id) do nothing;

create or replace function public.staff_message_approval_board()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then jsonb_build_object(
    'pending',count(*) filter(where ml.status='pending_approval'),
    'approved',count(*) filter(where ml.status='approved'),
    'sent',count(*) filter(where ml.status='sent'),
    'failed',count(*) filter(where ml.status='failed'),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',ml.id,'studentName',s.name,'recipientName',coalesce(ml.recipient_name,s.name),'recipientPhone',left(ml.recipient_phone,3)||'-****-'||right(ml.recipient_phone,4),
      'messageType',ml.message_type,'body',ml.body,'status',ml.status,'errorMessage',ml.error_message,'approvedBy',p.display_name,'approvedAt',ml.approved_at,'sentAt',ml.sent_at,'createdAt',ml.created_at
    ) order by ml.created_at desc),'[]'::jsonb)
  ) else null end
  from (select * from public.message_logs order by created_at desc limit 200) ml
  left join public.students s on s.id=ml.student_id left join public.profiles p on p.id=ml.approved_by
$$;

create or replace function public.staff_set_message_approval(p_message_ids uuid[],p_action text)
returns integer language plpgsql security definer set search_path=public as $$
declare changed_count integer;
begin
  if not public.is_staff() then raise exception '교직원만 문자 발송을 승인할 수 있습니다.'; end if;
  if coalesce(array_length(p_message_ids,1),0)=0 then raise exception '처리할 문자를 선택해 주세요.'; end if;
  if p_action='approve' then
    update public.message_logs set status='approved',approved_by=auth.uid(),approved_at=now(),cancelled_at=null,error_message=null where id=any(p_message_ids) and status in ('pending_approval','failed');
  elsif p_action='cancel' then
    update public.message_logs set status='cancelled',cancelled_at=now() where id=any(p_message_ids) and status in ('pending_approval','failed','approved');
  elsif p_action='retry' then
    update public.message_logs set status='pending_approval',approved_by=null,approved_at=null,error_message=null where id=any(p_message_ids) and status='failed';
  else raise exception '지원하지 않는 처리 방식입니다.';
  end if;
  get diagnostics changed_count=row_count; return changed_count;
end $$;

revoke all on function public.staff_message_approval_board() from public;
revoke all on function public.staff_set_message_approval(uuid[],text) from public;
grant execute on function public.staff_message_approval_board() to authenticated;
grant execute on function public.staff_set_message_approval(uuid[],text) to authenticated;
