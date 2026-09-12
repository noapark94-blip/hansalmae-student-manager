export type TaskStatus="completed"|"partial"|"incomplete"|null;
export type Report={id?:string;attendanceStatus?:string;lateMinutes?:number|null;absenceReason?:string;teacherInstruction?:string;examTitle?:string;examRange?:string;examScore?:number|null;examMaxScore?:number|null;evaluation?:string;homeworkInstruction?:string;homeworkStatus?:string|null;homeworkNote?:string;correctionContent?:string;correctionTaskStatus?:TaskStatus;correctionTaskFeedback?:string;assistantFeedback?:string;nextPreparation?:string;published?:boolean;recordedByName?:string|null;lastEditedByName?:string|null;updatedAt?:string|null};
export const editableReportKeys=["attendanceStatus","lateMinutes","absenceReason","teacherInstruction","examTitle","examRange","examScore","examMaxScore","evaluation","homeworkInstruction","homeworkStatus","homeworkNote","correctionContent","correctionTaskStatus","correctionTaskFeedback","assistantFeedback","nextPreparation","published"] as const;
export type EditableReportKey=(typeof editableReportKeys)[number];

export function reportValue(report:Report,field:EditableReportKey):unknown{
  if(field==="attendanceStatus")return report.attendanceStatus??"scheduled";
  if(field==="published")return report.published===true;
  if(field==="examMaxScore")return report.examMaxScore??100;
  if(field==="lateMinutes"||field==="examScore"||field==="homeworkStatus"||field==="correctionTaskStatus")return report[field]??null;
  return report[field]??"";
}
export function sameValue(left:unknown,right:unknown){return JSON.stringify(left)===JSON.stringify(right)}
export function mergeRemoteReport(local:Report,baseline:Report,remote:Report):Report{
  const merged:Report={...remote};
  for(const field of editableReportKeys)if(!sameValue(reportValue(local,field),reportValue(baseline,field)))Object.assign(merged,{[field]:local[field]});
  return merged;
}
export function mergeRemoteBaseline(local:Report,baseline:Report,remote:Report):Report{
  const merged:Report={...remote};
  for(const field of editableReportKeys)if(!sameValue(reportValue(local,field),reportValue(baseline,field)))Object.assign(merged,{[field]:baseline[field]});
  return merged;
}

export function conflictingReportFields(base:Report, local:Report, remote:Report):EditableReportKey[]{
  return editableReportKeys.filter(field=>!sameValue(reportValue(local,field),reportValue(base,field))&&!sameValue(reportValue(remote,field),reportValue(base,field))&&!sameValue(reportValue(remote,field),reportValue(local,field)));
}
export function resolveReportChoices(base:Report, compared:Report, latestLocal:Report, remote:Report, choices:Partial<Record<EditableReportKey,"mine"|"latest">>):Report{
  const merged=mergeRemoteReport(compared,base,remote);
  for(const field of editableReportKeys)if(choices[field]==="latest")Object.assign(merged,{[field]:remote[field]});
  return mergeRemoteReport(latestLocal,compared,merged);
}
