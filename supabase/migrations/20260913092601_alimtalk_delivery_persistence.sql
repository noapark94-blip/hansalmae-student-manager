-- Server-only recovery reads and idempotent resend-result writes.
-- Browser grants and RLS policies are unchanged.
grant select (id,status,provider_message_id,provider_group_id,error_message)
  on public.learning_alimtalk_deliveries to service_role;
grant select,insert,update
  on public.learning_alimtalk_resend_attempts to service_role;
