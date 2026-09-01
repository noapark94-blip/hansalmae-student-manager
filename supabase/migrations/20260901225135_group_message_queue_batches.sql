-- 같은 작성 동작에서 만든 문자들을 하나의 대기열 묶음으로 관리합니다.

alter table public.message_logs
  add column if not exists queue_batch_id uuid;

create index if not exists message_logs_queue_batch_idx
  on public.message_logs(queue_batch_id, created_at desc)
  where queue_batch_id is not null;

-- 기존 수동 대기열도 한 INSERT에서 생성되어 created_at이 완전히 같으므로 안전하게 묶습니다.
with existing_batches as (
  select body, message_type, created_at, gen_random_uuid() batch_id
  from public.message_logs
  where queue_batch_id is null and message_type = 'manual'
  group by body, message_type, created_at
)
update public.message_logs ml
set queue_batch_id = batch.batch_id
from existing_batches batch
where ml.queue_batch_id is null
  and ml.message_type = batch.message_type
  and ml.body = batch.body
  and ml.created_at = batch.created_at;

create or replace function public.staff_queue_selected_messages(p_student_ids uuid[], p_recipient_kind text, p_body text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  queued_count integer;
  v_batch_id uuid := gen_random_uuid();
begin
  if not public.is_staff() then raise exception '교직원만 문자를 발송 대기열에 등록할 수 있습니다.'; end if;
  if coalesce(array_length(p_student_ids,1),0)=0 then raise exception '발송할 학생을 선택해 주세요.'; end if;
  if array_length(p_student_ids,1)>500 then raise exception '한 번에 최대 500명까지 선택할 수 있습니다.'; end if;
  if p_recipient_kind not in ('student','guardian','both') then raise exception '수신자 유형을 선택해 주세요.'; end if;
  if nullif(trim(p_body),'') is null then raise exception '문자 내용을 입력해 주세요.'; end if;

  with target_students as (
    select distinct s.id,s.name,s.phone from public.students s
    where s.status in ('active','재원') and s.id=any(p_student_ids)
  ), recipients as (
    select ts.id student_id,ts.name recipient_name,ts.phone from target_students ts
    where p_recipient_kind in ('student','both') and nullif(trim(ts.phone),'') is not null
    union all
    select ts.id,g.name,g.phone from target_students ts join public.student_guardians sg on sg.student_id=ts.id join public.guardians g on g.id=sg.guardian_id
    where p_recipient_kind in ('guardian','both') and nullif(trim(g.phone),'') is not null
  ), deduplicated as (
    select distinct on (regexp_replace(phone,'[^0-9]','','g')) student_id,recipient_name,phone
    from recipients order by regexp_replace(phone,'[^0-9]','','g'),student_id
  )
  insert into public.message_logs(student_id,recipient_name,recipient_phone,message_type,body,provider,status,queue_batch_id)
  select student_id,recipient_name,phone,'manual',trim(p_body),'pending','pending_approval',v_batch_id from deduplicated;
  get diagnostics queued_count=row_count;
  return queued_count;
end
$$;

create or replace function public.staff_message_approval_board()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then jsonb_build_object(
    'pending',count(*) filter(where ml.status='pending_approval'),
    'approved',count(*) filter(where ml.status in ('approved','sending')),
    'sent',count(*) filter(where ml.status='sent'),
    'failed',count(*) filter(where ml.status='failed'),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',ml.id,'batchId',ml.queue_batch_id,'studentName',s.name,'recipientName',coalesce(ml.recipient_name,s.name),'recipientPhone',left(ml.recipient_phone,3)||'-****-'||right(ml.recipient_phone,4),
      'messageType',ml.message_type,'body',ml.body,'status',ml.status,'errorMessage',ml.error_message,'approvedBy',p.display_name,'approvedAt',ml.approved_at,'sentAt',ml.sent_at,'createdAt',ml.created_at
    ) order by ml.created_at desc),'[]'::jsonb)
  ) else null end
  from (select * from public.message_logs order by created_at desc limit 200) ml
  left join public.students s on s.id=ml.student_id left join public.profiles p on p.id=ml.approved_by
$$;

create or replace function public.staff_delete_message_logs(p_message_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  if not public.is_staff() then raise exception '교직원만 문자 대기 내역을 삭제할 수 있습니다.'; end if;
  if coalesce(array_length(p_message_ids,1),0)=0 then raise exception '삭제할 문자 대기 내역을 선택해 주세요.'; end if;
  if array_length(p_message_ids,1)>500 then raise exception '한 번에 최대 500건까지 삭제할 수 있습니다.'; end if;

  delete from public.message_logs
  where id=any(p_message_ids)
    and status in ('pending_approval','failed','cancelled');
  get diagnostics deleted_count=row_count;
  return deleted_count;
end
$$;

create or replace function public.staff_delete_message_log(p_message_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.staff_delete_message_logs(array[p_message_id]) = 1
$$;

revoke all on function public.staff_queue_selected_messages(uuid[],text,text) from public, anon;
revoke all on function public.staff_message_approval_board() from public, anon;
revoke all on function public.staff_delete_message_logs(uuid[]) from public, anon;
revoke all on function public.staff_delete_message_log(uuid) from public, anon;
grant execute on function public.staff_queue_selected_messages(uuid[],text,text) to authenticated;
grant execute on function public.staff_message_approval_board() to authenticated;
grant execute on function public.staff_delete_message_logs(uuid[]) to authenticated;
grant execute on function public.staff_delete_message_log(uuid) to authenticated;
