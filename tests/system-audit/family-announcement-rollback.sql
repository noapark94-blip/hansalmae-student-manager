begin;
do $test$
declare g record; aid uuid; sid uuid; author uuid; seen integer; cnt integer:=0;
begin
select id into author from public.profiles where role='admin' and is_active limit 1;
for g in select distinct gu.profile_id,gu.id guardian_id from public.guardians gu join public.profiles p on p.id=gu.profile_id where p.is_active loop
 perform set_config('request.jwt.claim.sub',g.profile_id::text,true);
 perform public.family_notification_center(); cnt:=cnt+1;
end loop;
if cnt=0 then raise exception 'no guardian fixtures'; end if;
select gu.profile_id,gu.id guardian_id into g from public.guardians gu join public.student_guardians sg on sg.guardian_id=gu.id join public.students s on s.id=sg.student_id where gu.profile_id is not null and s.status='active' limit 1;
select sg.student_id into sid from public.student_guardians sg join public.students s on s.id=sg.student_id where sg.guardian_id=g.guardian_id and s.status='active' limit 1;
insert into public.announcements(title,body,audience,student_id,author_profile_id,published_at) values('ROLLBACK TEST','No external message','student',sid,author,now()) returning id into aid;
perform set_config('request.jwt.claim.sub',g.profile_id::text,true);
perform public.family_notification_center();
perform public.family_notification_center();
select count(*) into seen from public.family_notifications where source_id=aid and recipient_profile_id=g.profile_id;
if seen<>1 then raise exception 'missing or duplicated announcement: %',seen; end if;
update public.announcements set expires_at=now()-interval '1 minute' where id=aid;
perform public.family_notification_center();
if exists(select 1 from public.family_notifications where source_id=aid and recipient_profile_id=g.profile_id) then raise exception 'expired announcement remains'; end if;
end $test$;
select 'PASS active guardian inboxes, announcement insertion, repeated sync and expiry' result;
rollback;
