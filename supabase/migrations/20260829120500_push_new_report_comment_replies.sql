-- Notify the family device only for a newly inserted staff reply.
-- Root family comments already appear in the staff inbox. Updates and deletes
-- never fire this INSERT-only trigger.

create or replace function public.dispatch_report_comment_reply_push()
returns trigger
language plpgsql
security definer
set search_path=public,vault,extensions
as $$
declare
  recipient_profile_id uuid;
  dispatch_key text;
  student_name text;
  author_name text;
begin
  if new.parent_id is null then return new; end if;

  select root.author_profile_id
  into recipient_profile_id
  from public.learning_report_comments root
  where root.id=new.parent_id;

  if recipient_profile_id is null then return new; end if;

  select decrypted_secret
  into dispatch_key
  from vault.decrypted_secrets
  where name='push_dispatch_webhook_key'
  limit 1;

  select name into student_name
  from public.students
  where id=new.student_id;

  select display_name into author_name
  from public.profiles
  where id=new.author_profile_id;

  perform net.http_post(
    url:='https://dngxryzhlbeiqpbdzndm.supabase.co/functions/v1/send-learning-feed-push',
    headers:=jsonb_build_object(
      'Content-Type','application/json',
      'x-push-dispatch-key',dispatch_key
    ),
    body:=jsonb_build_object(
      'kind','reply',
      'sourceKey',new.id::text,
      'studentIds',jsonb_build_array(new.student_id),
      'recipientProfileId',recipient_profile_id,
      'date',to_char(new.created_at at time zone 'Asia/Seoul','YYYY-MM-DD'),
      'title',case
        when nullif(regexp_replace(coalesce(author_name,''),'\\s*선생님$',''),'') is null then '선생님이 답장했어요'
        else regexp_replace(author_name,'\\s*선생님$','')||' 선생님이 답장했어요'
      end,
      'body',coalesce(student_name,'자녀')||' 학생의 학습 피드 댓글에 새 답장이 도착했습니다.',
      'url','/'
    )
  );

  return new;
end;
$$;

drop trigger if exists report_comment_reply_push on public.learning_report_comments;
create trigger report_comment_reply_push
after insert on public.learning_report_comments
for each row
when (new.parent_id is not null)
execute function public.dispatch_report_comment_reply_push();

revoke all on function public.dispatch_report_comment_reply_push()
from public,anon,authenticated;
