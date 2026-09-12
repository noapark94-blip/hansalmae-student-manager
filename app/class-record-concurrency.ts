export type EditValue = string | number | null;
export type EditValues = {notice:string;lessonContent:string;students:Record<string,Record<string,EditValue>>};
export type EditChange = {path:string[];before:EditValue;value:EditValue};
export function editChanges(base:EditValues,next:EditValues):EditChange[]{
 const changes:EditChange[]=[];
 for(const key of ['notice','lessonContent'] as const) if(base[key]!==next[key])changes.push({path:[key],before:base[key],value:next[key]});
 for(const [id,row] of Object.entries(next.students)){
  const old=base.students[id]; if(!old)throw new Error("수업 명단이 변경됐습니다. 입력 내용을 보관한 뒤 최신 명단을 확인해 주세요.");
  for(const [key,value] of Object.entries(row))if(key!=='exam_id'&&value!==old[key])changes.push({path:['students',id,key],before:old[key],value});
  if(changes.some(c=>c.path[1]===id&&c.path[2]?.startsWith('exam_')))changes.push({path:['students',id,'exam_id'],before:old.exam_id,value:old.exam_id});
 }
 return changes;
}
// Refreshes may encounter retained input for a student no longer in the baseline.
// Keep it visible for explicit review; strict save diffing still rejects it.
function knownStudentValues(local:EditValues,base:EditValues):EditValues {
 return {...local,students:Object.fromEntries(Object.entries(local.students).filter(([id])=>Boolean(base.students[id])))};
}
// Preserve only input changed after the request began; adopt the server's other values.
export function preservePendingEdits(local:EditValues,submitted:EditValues,remote:EditValues):EditValues{
 const result:EditValues=structuredClone(remote);
 for(const c of editChanges(submitted,knownStudentValues(local,submitted))){
  if(c.path[2]==='exam_id')continue;
  if(c.path.length===1)result[c.path[0] as 'notice'|'lessonContent']=String(c.value??'');
  else {result.students[c.path[1]]??=structuredClone(local.students[c.path[1]]);result.students[c.path[1]][c.path[2]]=c.value;}
 }
 for(const [id,row] of Object.entries(local.students))if(!submitted.students[id])result.students[id]=structuredClone(row);
 return result;
}
// Dirty fields retain their original baseline so a later save still detects conflicts.
export function mergeLiveEditValues(base:EditValues,local:EditValues,remote:EditValues) {
 const values=preservePendingEdits(local,base,remote);
 const baseline=structuredClone(remote);
 for(const change of editChanges(base,knownStudentValues(local,base))){
  if(change.path.length===1)baseline[change.path[0] as 'notice'|'lessonContent']=String(change.before??'');
  else {const id=change.path[1];baseline.students[id]??=structuredClone(base.students[id]);baseline.students[id][change.path[2]]=change.before;}
 }
 return {values,baseline};
}
