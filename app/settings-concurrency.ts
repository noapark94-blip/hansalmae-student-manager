function canonical(value:unknown):unknown {
  if(Array.isArray(value))return value.map(canonical);
  if(value&&typeof value==="object")return Object.fromEntries(Object.entries(value).sort(([a],[b])=>a.localeCompare(b)).map(([key,item])=>[key,canonical(item)]));
  return value;
}
export function settingsChanges<T extends object>(base:T,mine:T) {
  return Object.fromEntries(Object.entries(mine).filter(([key,value])=>JSON.stringify(canonical(value))!==JSON.stringify(canonical(base[key as keyof T]))));
}
export function mergeSettingsChoices<T extends object>(base:T,mine:T,latest:T,choices:Record<string,"mine"|"latest">):T {
  return {...latest,...Object.fromEntries(Object.entries(settingsChanges(base,mine)).filter(([key])=>choices[key]!=="latest"))};
}
export function classSettingsValues(row:{name:string;subjectId:string|null;room:string|null;color:string;teachers:{id:string}[];schedules:{weekday:number;startTime:string;endTime:string}[]}) {
  return {name:row.name.trim(),subjectId:row.subjectId??"",room:row.room?.trim()??"",color:row.color,
    teacherIds:[...new Set(row.teachers.map(x=>x.id))].sort(),
    schedules:row.schedules.map(x=>({weekday:x.weekday,startTime:x.startTime.slice(0,5),endTime:x.endTime.slice(0,5)})).sort((a,b)=>a.weekday-b.weekday||a.startTime.localeCompare(b.startTime)||a.endTime.localeCompare(b.endTime))};
}
export function calendarValues(v:{scope:string;category:string;startsOn:string;endsOn:string;startsAt:string|null;endsAt:string|null;school:string|null;grade:string|null;title:string;classId:string|null;teacherId:string|null;note:string|null;contactName:string|null;contactPhone:string|null;location:string|null;status:string}) {
  return {kind:{scope:v.scope,category:v.category},timing:{startsOn:v.startsOn,endsOn:v.endsOn,startsAt:v.startsAt?.slice(0,5)??"",endsAt:v.endsAt?.slice(0,5)??""},
    school:v.school?.trim()??"",grade:v.grade??"",title:v.title.trim(),classId:v.classId??"",teacherId:v.teacherId??"",
    note:v.note?.trim()??"",contactName:v.contactName?.trim()??"",contactPhone:v.contactPhone?.trim()??"",location:v.location?.trim()??"",status:v.status};
}
