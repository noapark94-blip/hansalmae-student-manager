begin;
do $test$
declare delivery uuid; actor uuid; attempt uuid:=gen_random_uuid(); n integer;
begin
select id into delivery from public.learning_alimtalk_deliveries limit 1;
select id into actor from public.profiles where role='admin' and is_active limit 1;
if delivery is null or actor is null then raise exception 'test fixture unavailable'; end if;
perform set_config('role','service_role',true);
perform id,status,provider_message_id,provider_group_id,error_message from public.learning_alimtalk_deliveries where id=delivery;
insert into public.learning_alimtalk_resend_attempts(id,delivery_id,status,provider_message_id,created_by,sent_at)
values(attempt,delivery,'sent','mock-no-message-sent',actor,now())
on conflict(id) do update set status=excluded.status,provider_message_id=excluded.provider_message_id;
insert into public.learning_alimtalk_resend_attempts(id,delivery_id,status,provider_message_id,created_by,sent_at)
values(attempt,delivery,'sent','mock-no-message-sent',actor,now())
on conflict(id) do update set status=excluded.status,provider_message_id=excluded.provider_message_id;
select count(*) into n from public.learning_alimtalk_resend_attempts where id=attempt;
if n<>1 then raise exception 'duplicate attempt after retry'; end if;
perform set_config('role','postgres',true);
if has_table_privilege('anon','public.learning_alimtalk_resend_attempts','INSERT') or has_table_privilege('authenticated','public.learning_alimtalk_resend_attempts','INSERT') then raise exception 'browser write access'; end if;
end $test$;
select 'PASS server readback and idempotent resend persistence; no external messages' as result;
rollback;
