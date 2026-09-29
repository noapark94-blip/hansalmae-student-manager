import type { Course } from "./engine";
export function combineCourses(members: Course[], settings: {id:string;name:string;teacherId:string;count:number;duration:number;room:string}): Course {
  if(members.length<2 || new Set(members.map(c=>c.id)).size!==members.length)throw new Error("서로 다른 반을 2개 이상 선택해 주세요.");
  if(members.some(c=>c.memberCourses?.length) || new Set(members.map(c=>c.subject)).size!==1)throw new Error("같은 과목의 일반 클래스끼리 합반할 수 있습니다.");
  if(!settings.name.trim()||!settings.teacherId)throw new Error("합반 이름과 담당 선생님을 입력해 주세요.");
  return {id:settings.id,name:settings.name.trim(),teachers:[settings.teacherId],count:settings.count,duration:settings.duration,room:settings.room.trim(),subject:members[0].subject,enabled:true,high:members.some(c=>c.high),students:[...new Map(members.flatMap(c=>c.students).map(s=>[s.id,s])).values()],memberCourses:members};
}
export function updateMerge(courses:Course[], merged:Course, previousId?:string):Course[]{
  const members=new Set(merged.memberCourses!.map(c=>c.id));
  const previous=courses.find(c=>c.id===previousId);
  const released=(previous?.memberCourses??[]).filter(c=>!members.has(c.id));
  return [...courses.filter(c=>c.id!==previousId&&!members.has(c.id)),...released,merged];
}
export function releaseMerge(courses:Course[], id:string):Course[]{
  return courses.flatMap(c=>c.id===id&&c.memberCourses?.length?c.memberCourses:[c]);
}
