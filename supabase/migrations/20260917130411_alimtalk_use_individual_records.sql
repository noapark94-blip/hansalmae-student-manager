-- Alimtalk must respect individual lesson/homework fields, including cleared values.
-- Replace only the two regular-class fallback expressions; preserve grants and other sources.
do $migration$
declare
  definition text := pg_get_functiondef('public.internal_alimtalk_report_sources(uuid[],date,date)'::regprocedure);
  old_lesson text := $old$coalesce(nullif(trim(hr.lesson_content),''), l.lesson_content, '')$old$;
  old_homework text := $old$coalesce(nullif(trim(hr.assigned_homework), ''), nullif(trim(l.homework_content), ''), '')$old$;
begin
  if strpos(definition,old_lesson)=0 or strpos(definition,old_homework)=0 then
    raise exception 'Unexpected Alimtalk source definition; review before applying';
  end if;
  definition := replace(definition,old_lesson,$new$coalesce(hr.lesson_content, '')$new$);
  definition := replace(definition,old_homework,$new$coalesce(hr.assigned_homework, '')$new$);
  execute definition;
end
$migration$;
