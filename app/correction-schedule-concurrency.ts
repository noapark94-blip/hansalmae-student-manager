export type ScheduleValues={studentId:string;subject:string;schedule:{weekday:number;startTime:string;endTime:string};tutorId:string;supervisorId:string;note:string};
export function assignmentValues(row:{studentId:string;subject:string;weekday:number;startTime:string;endTime:string;tutorId?:string|null;supervisorId?:string|null;note?:string|null}):ScheduleValues{
 return {studentId:row.studentId,subject:row.subject,schedule:{weekday:row.weekday,startTime:row.startTime.slice(0,5),endTime:row.endTime.slice(0,5)},tutorId:row.tutorId??'',supervisorId:row.supervisorId??'',note:row.note??''};
}
export function scheduleChanges(base:ScheduleValues,next:ScheduleValues):Partial<ScheduleValues>{
 return Object.fromEntries((Object.keys(base) as (keyof ScheduleValues)[]).filter(k=>JSON.stringify(base[k])!==JSON.stringify(next[k])).map(k=>[k,next[k]]));
}
export function mergeScheduleChoices(base:ScheduleValues,local:ScheduleValues,remote:ScheduleValues,choices:Record<string,'mine'|'latest'>):ScheduleValues{
 const changes=scheduleChanges(base,local);
 for(const key of Object.keys(choices))if(choices[key]==='latest')delete changes[key as keyof ScheduleValues];
 return {...remote,...changes};
}
export function slotMembershipChanges(base:Set<string>,next:Set<string>){
 return [...new Set([...base,...next])].filter(k=>base.has(k)!==next.has(k)).map(k=>{const [weekday,startTime,...id]=k.split('-');return {weekday:Number(weekday),startTime,assistantId:id.join('-'),selected:next.has(k)};});
}
export function exceptionValues(e:{assignmentId:string;originalDate:string;kind:string;targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null;note:string|null}){
 return {...e,targetStartTime:e.targetStartTime?.slice(0,5)??null,targetEndTime:e.targetEndTime?.slice(0,5)??null,note:e.note??''};
}
