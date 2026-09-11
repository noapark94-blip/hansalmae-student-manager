-- Isolated contract fixture for the new RPC; no production records or credentials.
create role anon; create role authenticated;
create schema auth;
create function auth.uid() returns uuid language sql as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
create function public.is_staff() returns boolean language sql as $$select true$$;
create function public.current_user_role() returns text language sql as $$select 'admin'::text$$;
create type public.attendance_status as enum ('present','late','absent','excused');
create table class_teachers(class_id uuid,profile_id uuid);
create table lessons(id uuid primary key,class_id uuid,lesson_date date,status text,starts_at time);
create table fixture_store(id int primary key, payload jsonb, revision jsonb);
insert into fixture_store values(1,'{"notice":"","lessonContent":"","rows":[{"studentId":"00000000-0000-0000-0000-000000000011","status":"present","lateMinutes":null,"exam":{},"assignedHomework":""},{"studentId":"00000000-0000-0000-0000-000000000012","status":"present","lateMinutes":null,"exam":{},"assignedHomework":""}]}',null);
insert into lessons values('00000000-0000-0000-0000-000000000099','00000000-0000-0000-0000-000000000002','2026-09-11','draft','16:00');
create function staff_class_exam_results(uuid,date) returns jsonb language sql stable as $$select jsonb_agg(jsonb_build_object('studentId',r->>'studentId','exams',case when r->'exam'='{}' then '[]'::jsonb else jsonb_build_array(r->'exam') end)) from fixture_store,jsonb_array_elements(payload->'rows') r$$;
create function staff_class_homework_results(uuid,date) returns jsonb language sql stable as $$select payload->'rows' from fixture_store$$;
create function staff_class_day(uuid,date) returns jsonb language sql stable as $$select jsonb_build_object('students',jsonb_agg(r||jsonb_build_object('id',r->>'studentId'))) from fixture_store,jsonb_array_elements(payload->'rows') r$$;
create function staff_class_revision_draft(uuid,date) returns jsonb language sql stable as $$select case when revision is null then null else jsonb_build_object('payload',revision,'savedAt',now()) end from fixture_store$$;
create function staff_class_daily_notice(uuid,date) returns text language sql stable as $$select payload->>'notice' from fixture_store$$;
create function staff_class_lesson_content(uuid,date) returns text language sql stable as $$select payload->>'lessonContent' from fixture_store$$;
create function staff_save_class_homework_results(uuid,date,p_results jsonb) returns void language plpgsql as $$declare item jsonb;begin
 for item in select value from jsonb_array_elements(p_results) loop
 update fixture_store set payload=jsonb_set(payload,'{rows}',(select jsonb_agg(case when r->>'studentId'=item->>'studentId' then r|| (item-'status'-'lateMinutes'-'absenceReason'-'note') else r end) from jsonb_array_elements(payload->'rows') r));
 end loop;end$$;
create function staff_save_class_exam_results(uuid,date,p_results jsonb) returns void language plpgsql as $$declare item jsonb;begin
 for item in select value from jsonb_array_elements(p_results) loop
 if (item->'exams'->0->>'score')::numeric>100 then raise exception 'invalid score';end if;
 update fixture_store set payload=jsonb_set(payload,'{rows}',(select jsonb_agg(case when r->>'studentId'=item->>'studentId' then r||jsonb_build_object('exam',item->'exams'->0) else r end) from jsonb_array_elements(payload->'rows') r));
 end loop;end$$;
create function staff_save_class_daily_notice(uuid,date,p_content text) returns void language sql as $$update fixture_store set payload=jsonb_set(payload,'{notice}',to_jsonb(p_content))$$;
create function staff_save_class_lesson_content(uuid,date,p_content text) returns void language sql as $$update fixture_store set payload=jsonb_set(payload,'{lessonContent}',to_jsonb(p_content))$$;
create function staff_set_class_lesson_state(uuid,date,p_state text) returns text language plpgsql as $$begin update lessons set status=p_state;return p_state;end$$;
create function staff_save_class_revision_draft(uuid,date,p_payload jsonb) returns timestamptz language plpgsql as $$begin update fixture_store set revision=p_payload;return now();end$$;
create function staff_publish_class_revision(uuid,date,p_payload jsonb) returns void language sql as $$update fixture_store set payload=p_payload,revision=null$$;
create function staff_clear_class_attendance(uuid,date,uuid) returns void language plpgsql as $$begin raise exception 'not used in this contract';end$$;
create function staff_save_class_attendance(uuid,date,uuid,attendance_status,integer,text,text) returns void language plpgsql as $$begin raise exception 'not used in this contract';end$$;
