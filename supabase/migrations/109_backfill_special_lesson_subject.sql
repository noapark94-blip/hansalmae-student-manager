with teacher_subjects as (
  select ct.profile_id,
         min(c.subject_id::text)::uuid as subject_id
  from public.class_teachers ct
  join public.classes c on c.id=ct.class_id and c.active and c.subject_id is not null
  group by ct.profile_id
  having count(distinct c.subject_id)=1
)
update public.teacher_special_lessons lesson
set subject_id=teacher_subjects.subject_id,
    updated_at=now()
from teacher_subjects
where lesson.teacher_profile_id=teacher_subjects.profile_id
  and lesson.subject_id is null;
