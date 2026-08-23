-- Edge Function이 테이블 직접 권한 없이 문자 발송 결과만 제한적으로 기록하도록 합니다.

create or replace function public.internal_fail_message_delivery(p_message_ids uuid[], p_error_message text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare changed integer;
begin
  if coalesce(array_length(p_message_ids,1),0)=0 or array_length(p_message_ids,1)>500 then
    raise exception '올바른 문자 식별자가 필요합니다.';
  end if;
  update public.message_logs
  set status='failed',error_message=left(coalesce(nullif(trim(p_error_message),''),'문자 발송 중 오류가 발생했습니다.'),500),sending_at=null
  where id=any(p_message_ids) and status='sending';
  get diagnostics changed=row_count;
  return changed;
end
$$;

create or replace function public.internal_finish_message_delivery(
  p_message_id uuid,
  p_status text,
  p_provider_message_id text,
  p_provider_group_id text,
  p_error_message text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('sent','failed') then raise exception '올바른 발송 결과가 필요합니다.'; end if;
  update public.message_logs set
    status=p_status,
    provider='solapi',
    provider_message_id=nullif(p_provider_message_id,''),
    provider_group_id=nullif(p_provider_group_id,''),
    error_message=case when p_status='failed' then left(coalesce(nullif(trim(p_error_message),''),'솔라피에서 발송 접수 결과를 확인하지 못했습니다.'),500) else null end,
    sending_at=null,
    sent_at=case when p_status='sent' then now() else sent_at end
  where id=p_message_id and status='sending';
  return found;
end
$$;

revoke all on function public.internal_fail_message_delivery(uuid[],text) from public, anon, authenticated;
revoke all on function public.internal_finish_message_delivery(uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function public.internal_fail_message_delivery(uuid[],text) to service_role;
grant execute on function public.internal_finish_message_delivery(uuid,text,text,text,text) to service_role;

update public.message_logs
set status='failed',sending_at=null,error_message='이전 발송 요청이 서버 권한 오류로 중단되었습니다. 다시 시도해 주세요.'
where status='sending' and provider_message_id is null;
