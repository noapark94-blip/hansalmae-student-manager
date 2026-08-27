-- 학부모와 담당 교직원이 리포트 댓글에 남기는 한 가지 반응
create table if not exists public.learning_report_comment_reactions (
  comment_id uuid not null references public.learning_report_comments(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null check (reaction in ('heart','confirm','done','thanks')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (comment_id,profile_id)
);

alter table public.learning_report_comment_reactions enable row level security;
revoke all on table public.learning_report_comment_reactions from public,anon,authenticated;

create or replace function public.report_comment_reactions(p_comment_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  with accessible as (
    select c.id
    from public.learning_report_comments c
    where c.id=any(coalesce(p_comment_ids,array[]::uuid[]))
      and c.deleted_at is null
      and (
        (public.current_user_role()='guardian' and public.can_view_family_report(c.student_id,c.lesson_id))
        or (public.current_user_role() in ('admin','teacher','manager') and public.can_manage_family_report_comment(c.student_id,c.lesson_id))
      )
  ), grouped as (
    select r.comment_id,r.reaction,count(*)::int as total,bool_or(r.profile_id=auth.uid()) as selected
    from public.learning_report_comment_reactions r join accessible a on a.id=r.comment_id
    group by r.comment_id,r.reaction
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'commentId',a.id,
    'reactions',coalesce((select jsonb_agg(jsonb_build_object('type',g.reaction,'count',g.total,'selected',g.selected) order by g.reaction) from grouped g where g.comment_id=a.id),'[]'::jsonb)
  ) order by a.id),'[]'::jsonb) into result from accessible a;
  return result;
end $$;

create or replace function public.toggle_report_comment_reaction(p_comment_id uuid,p_reaction text)
returns void language plpgsql security definer set search_path=public as $$
declare target public.learning_report_comments; existing text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if p_reaction not in ('heart','confirm','done','thanks') then raise exception '지원하지 않는 반응입니다.'; end if;
  select * into target from public.learning_report_comments where id=p_comment_id and deleted_at is null;
  if target.id is null then raise exception '댓글을 찾을 수 없습니다.'; end if;
  if not (
    (public.current_user_role()='guardian' and public.can_view_family_report(target.student_id,target.lesson_id))
    or (public.current_user_role() in ('admin','teacher','manager') and public.can_manage_family_report_comment(target.student_id,target.lesson_id))
  ) then raise exception '이 댓글에 반응할 권한이 없습니다.'; end if;
  select reaction into existing from public.learning_report_comment_reactions where comment_id=p_comment_id and profile_id=auth.uid();
  if existing=p_reaction then
    delete from public.learning_report_comment_reactions where comment_id=p_comment_id and profile_id=auth.uid();
  else
    insert into public.learning_report_comment_reactions(comment_id,profile_id,reaction)
    values(p_comment_id,auth.uid(),p_reaction)
    on conflict(comment_id,profile_id) do update set reaction=excluded.reaction,updated_at=now();
  end if;
end $$;

revoke all on function public.report_comment_reactions(uuid[]),public.toggle_report_comment_reaction(uuid,text) from public,anon;
grant execute on function public.report_comment_reactions(uuid[]),public.toggle_report_comment_reaction(uuid,text) to authenticated;
notify pgrst,'reload schema';
