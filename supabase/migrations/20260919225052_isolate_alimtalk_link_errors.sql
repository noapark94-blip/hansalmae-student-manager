-- Source links are optional metadata. Lookup/serialization failures must not
-- discard a valid delivery or alter its exact saved template variables.
create or replace function public.internal_capture_alimtalk_source_refs()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 begin
  new.source_refs:=public.internal_alimtalk_source_refs(public.staff_learning_report_source(new.student_id,new.period_start,new.period_end));
 exception when others then
  -- NULL invokes the existing legacy lookup when the user opens a link.
  -- Never keep references belonging to the previous failed delivery content.
  new.source_refs:=null;
 end;
 return new;
end $$;
revoke all on function public.internal_capture_alimtalk_source_refs() from public,anon,authenticated;
