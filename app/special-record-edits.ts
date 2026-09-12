import type {EditValues} from './class-record-concurrency';
export type SpecialExam={examType:string;examTitle:string;score:string;maxScore:string;evaluation:string};
export type SpecialEditable={id:string;lessonContent:string;assignedHomework:string;inspectionStatus:string;inspectionNote:string;exam:SpecialExam};
export function specialInputValues(base:EditValues,rows:SpecialEditable[],notice:string):EditValues{
 const values=structuredClone(base);values.notice=notice;
 for(const row of rows){const v=values.students[row.id];if(!v)continue;
  for(const key of ['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] as const)v[key]=row[key];
  for(const key of ['examType','examTitle','evaluation'] as const)v['exam_'+key]=row.exam[key];
  v.exam_score=row.exam.score===''?'':String(Number(row.exam.score));v.exam_maxScore=String(Number(row.exam.maxScore||100));
 }return values;
}
export function applySpecialValues<T extends SpecialEditable>(rows:T[],values:EditValues):T[]{return rows.map(row=>{const v=values.students[row.id];if(!v)return row;return {...row,lessonContent:String(v.lessonContent??''),assignedHomework:String(v.assignedHomework??''),inspectionStatus:String(v.inspectionStatus??''),inspectionNote:String(v.inspectionNote??''),exam:{examType:String(v.exam_examType??''),examTitle:String(v.exam_examTitle??''),score:String(v.exam_score??''),maxScore:String(v.exam_maxScore??'100'),evaluation:String(v.exam_evaluation??'')}};});}
