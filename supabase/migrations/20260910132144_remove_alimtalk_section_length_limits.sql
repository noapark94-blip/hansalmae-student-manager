do $migration$
declare definition text;
begin
  select pg_get_functiondef('public.staff_claim_learning_alimtalk(uuid,text,date,date,text,text,text)'::regprocedure) into definition;
  if position('not between 1 and 180' in definition)=0 then raise exception 'Expected legacy validation not found'; end if;
  definition:=replace(replace(definition,'not between 1 and 180','< 1'),'not between 1 and 100','< 1');
  definition:=replace(definition,'알림톡 요약 내용을 확인해 주세요.','수업·출결·학습 요약에 빈 항목이 있습니다. 내용을 확인해 주세요.');
  execute definition;
end $migration$;
notify pgrst,'reload schema';