-- 승인된 문자 발송을 SOLAPI와 안전하게 연결하고 중복 실행을 방지합니다.

alter table public.message_logs
  add column if not exists sending_at timestamptz,
  add column if not exists delivery_attempts integer not null default 0,
  add column if not exists provider_group_id text;

create or replace function public.staff_claim_message_delivery(p_message_ids uuid[])
returns table(id uuid, recipient_phone text, body text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 문자를 발송할 수 있습니다.';
  end if;
  if coalesce(array_length(p_message_ids, 1), 0) = 0 then
    raise exception '발송할 문자를 선택해 주세요.';
  end if;
  if array_length(p_message_ids, 1) > 500 then
    raise exception '한 번에 최대 500건까지 발송할 수 있습니다.';
  end if;

  -- 네트워크 중단으로 오래 멈춘 요청은 다시 선택할 수 있게 실패로 돌립니다.
  update public.message_logs ml
  set status = 'failed',
      error_message = '이전 발송 요청이 완료되지 않았습니다. 다시 시도해 주세요.',
      sending_at = null
  where ml.status = 'sending'
    and ml.sending_at < now() - interval '10 minutes';

  return query
  update public.message_logs ml
  set status = 'sending',
      provider = 'solapi',
      approved_by = auth.uid(),
      approved_at = now(),
      cancelled_at = null,
      sending_at = now(),
      delivery_attempts = ml.delivery_attempts + 1,
      error_message = null
  where ml.id = any(p_message_ids)
    and ml.status in ('pending_approval', 'failed')
  returning ml.id, ml.recipient_phone, ml.body;
end
$$;

revoke all on function public.staff_claim_message_delivery(uuid[]) from public;
grant execute on function public.staff_claim_message_delivery(uuid[]) to authenticated;

create index if not exists message_logs_delivery_status_idx
  on public.message_logs(status, sending_at)
  where status in ('pending_approval', 'sending', 'failed');

create or replace function public.staff_message_approval_board()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then jsonb_build_object(
    'pending',count(*) filter(where ml.status='pending_approval'),
    'approved',count(*) filter(where ml.status in ('approved','sending')),
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
