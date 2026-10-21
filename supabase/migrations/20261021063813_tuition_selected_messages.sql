-- Tuition messages use existing approval/delivery; no messages are sent by this migration.
alter table public.message_logs add column if not exists tuition_context jsonb;
create unique index if not exists tuition_message_request_phone on public.message_logs(queue_batch_id,recipient_phone) where tuition_context is not null;

create or replace function public.staff_preview_tuition_messages(p_month date,p_charge_ids uuid[],p_template text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_rows jsonb; v_snapshot jsonb; v_recipients jsonb; v_history jsonb;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 원비 문자를 작성할 수 있습니다.'; end if;
 if p_month is null or coalesce(cardinality(p_charge_ids),0) not between 1 and 500 then raise exception '원비 월과 대상 학생을 선택해 주세요.'; end if;
 if nullif(trim(p_template),'') is null or length(p_template)>1500 then raise exception '문자 내용을 1~1500자로 입력해 주세요.'; end if;
 select coalesce(jsonb_agg(r order by r->>'id'),'[]'::jsonb) into v_rows
 from jsonb_array_elements(public.tuition_board(p_month)->'items') r where (r->>'id')::uuid=any(p_charge_ids);
 if jsonb_array_length(v_rows)<>(select count(distinct x) from unnest(p_charge_ids) x) then raise exception '청구 정보가 변경되었습니다. 원비 목록을 새로고침해 주세요.'; end if;
 select jsonb_agg(jsonb_build_object('id',r->'id','studentId',r->'studentId','studentName',r->'studentName','grade',r->'grade','school',r->'school','status',r->'status','totalAmount',r->'totalAmount','paidAmount',r->'paidAmount','balance',r->'balance','guardianPhones',r->'guardianPhones') order by r->>'id') into v_snapshot from jsonb_array_elements(v_rows) r;
 with contacts as (
  select distinct r,regexp_replace(phone,'[^0-9]','','g') phone
  from jsonb_array_elements(v_rows) r cross join lateral jsonb_array_elements_text(coalesce(r->'guardianPhones','[]')) phone
 ), rendered as (
  select r,phone,replace(replace(replace(replace(replace(replace(p_template,
   '{학생명}',r->>'studentName'),'{월}',to_char(p_month,'YYYY년 FMMM월')),
   '{청구액}',to_char((r->>'totalAmount')::numeric,'FM999,999,999,990')),
   '{납부액}',to_char((r->>'paidAmount')::numeric,'FM999,999,999,990')),
   '{미납액}',to_char((r->>'balance')::numeric,'FM999,999,999,990')),
   '{납부상태}',case r->>'status' when 'paid' then '납부 완료' when 'partial' then '부분 납부' when 'waived' then '면제' else '미납' end) body
  from contacts where phone ~ '^01[016789][0-9]{7,8}$'
 ), grouped as (
  select phone,string_agg(body,E'\n\n' order by r->>'studentName',r->>'id') body,
   jsonb_agg(jsonb_build_object('chargeId',r->'id','studentId',r->'studentId','name',r->'studentName') order by r->>'id') students
  from rendered group by phone
 ) select coalesce(jsonb_agg(jsonb_build_object('phone',phone,'body',body,'students',students) order by phone),'[]'::jsonb) into v_recipients from grouped;
 if exists(select 1 from jsonb_array_elements(v_recipients) r where octet_length(r->>'body')>2000) then raise exception '문자 길이가 너무 깁니다. 형제자매 합산 내용을 포함해 문구를 줄여 주세요.'; end if;
 select coalesce(jsonb_agg(h),'[]'::jsonb) into v_history from (
  select distinct on (s->>'chargeId') s->>'chargeId' as "chargeId",ml.status,coalesce(ml.sent_at,ml.created_at) as "at"
  from public.message_logs ml
  cross join lateral jsonb_array_elements(ml.tuition_context->'expected'->'recipients') r
  cross join lateral jsonb_array_elements(r->'students') s
  where ml.tuition_context->>'month'=p_month::text and r->>'phone'=ml.recipient_phone and (s->>'chargeId')::uuid=any(p_charge_ids)
  order by s->>'chargeId',ml.created_at desc
 ) h;
 return jsonb_build_object('snapshot',v_snapshot,'recipients',v_recipients,'history',v_history);
end $$;

create or replace function public.staff_queue_tuition_messages(p_month date,p_charge_ids uuid[],p_template text,p_expected jsonb,p_request_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare v_preview jsonb; v_count integer;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 원비 문자를 작성할 수 있습니다.'; end if;
 if p_request_id is null then raise exception '요청 번호가 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,0));
 select count(*) into v_count from public.message_logs where queue_batch_id=p_request_id and tuition_context is not null;
 if v_count>0 then return v_count; end if;
 v_preview:=public.staff_preview_tuition_messages(p_month,p_charge_ids,p_template);
 if p_expected is null or (v_preview-'history') is distinct from (p_expected-'history') then raise exception '납부 상태·금액 또는 연락처가 변경되었습니다. 미리보기를 다시 확인해 주세요.'; end if;
 if jsonb_array_length(v_preview->'recipients')=0 then raise exception '유효한 학부모 휴대폰 번호가 없습니다.'; end if;
 insert into public.message_logs(student_id,recipient_name,recipient_phone,message_type,body,provider,status,queue_batch_id,tuition_context)
 select (r->'students'->0->>'studentId')::uuid,
  (select string_agg(s->>'name',' · ') from jsonb_array_elements(r->'students') s)||' 학부모',
  r->>'phone','manual',r->>'body','pending','pending_approval',p_request_id,
  jsonb_build_object('month',p_month,'ids',to_jsonb(p_charge_ids),'template',p_template,'expected',v_preview)
 from jsonb_array_elements(v_preview->'recipients') r;
 get diagnostics v_count=row_count;
 return v_count;
end $$;

-- Recheck at the existing sender's claim step, before any paid delivery request.
create or replace function public.guard_tuition_message_delivery()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_current jsonb; v_ids uuid[];
begin
 if new.status='sending' and old.status is distinct from 'sending' and new.tuition_context is not null then
  select array_agg(x::uuid) into v_ids from jsonb_array_elements_text(new.tuition_context->'ids') x;
  v_current:=public.staff_preview_tuition_messages((new.tuition_context->>'month')::date,v_ids,new.tuition_context->>'template');
  if (v_current-'history') is distinct from ((new.tuition_context->'expected')-'history') then raise exception '원비 납부 정보 또는 연락처가 변경되었습니다. 해당 원비 문자를 삭제하고 원비 화면에서 다시 작성해 주세요.'; end if;
 end if;
 return new;
end $$;
create trigger guard_tuition_message_delivery before update of status on public.message_logs for each row execute function public.guard_tuition_message_delivery();
revoke all on function public.staff_preview_tuition_messages(date,uuid[],text), public.staff_queue_tuition_messages(date,uuid[],text,jsonb,uuid), public.guard_tuition_message_delivery() from public,anon;
grant execute on function public.staff_preview_tuition_messages(date,uuid[],text), public.staff_queue_tuition_messages(date,uuid[],text,jsonb,uuid) to authenticated;
