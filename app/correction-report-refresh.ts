import {createCorrectionRefreshQueue} from "./correction-live-refresh";
export type ReportRequest={assignmentId:string;date:string;startTime:string};
export const correctionRequestKey=(row:ReportRequest)=>`${row.assignmentId}-${row.date}-${row.startTime}`;

export function createCorrectionReportRefresh<T>(
 read:(records:ReportRequest[])=>Promise<T[]>,
 apply:(records:ReportRequest[],rows:T[])=>void,
 onError:(error:unknown)=>void,
 options:{delay?:number;visible?:()=>boolean}={},
) {
 const known=new Map<string,ReportRequest>();
 let disposed=false;
 const queue=createCorrectionRefreshQueue(async batch=>{
   const records=(batch.full?[...known.keys()]:batch.ids).flatMap(key=>known.has(key)?[known.get(key)!]:[]);
   // Existing RPC accepts at most 500 records, including entries with no saved report.
   for(let offset=0;offset<records.length;offset+=500){
     if(disposed)return;
     const chunk=records.slice(offset,offset+500);
     const rows=await read(chunk);
     if(disposed)return;
     if(rows.length!==chunk.length)throw new Error("첨삭 기록 일부를 불러오지 못했습니다.");
     apply(chunk,rows);
   }
 },onError,options);
 return {
   changed(row:ReportRequest){if(disposed)return;const key=correctionRequestKey(row);known.set(key,row);queue.request({id:key});},
   resume(){queue.request();},
   dispose(){disposed=true;queue.dispose();known.clear();},
 };
}
