export type ExportCharge = {
 id:string; studentId:string; studentName:string; school:string|null; grade:string|null;
 subjects:string[]; classNames:string[]; lineItems:{className:string;amount:number}[];
 totalAmount:number; paidAmount:number; status:'open'|'partial'|'paid'|'waived'; memo:string|null;
 payments:{id:string;amount:number;method:string;paidAt:string}[];
};
export type ExportEntry = ExportCharge & {month:string};
export const statusLabels = {open:'미납',partial:'부분 납부',paid:'납부 완료',waived:'면제'};
export const exportColumns = [
 ['studentName','학생명',16],['school','학교',28],['grade','학년',10],['subjects','수강 과목',32],
 ['classes','수강반',38],['total','원비',16],['paid','납부액',16],['waived','면제액',16],
 ['balance','미납액',16],['date','납부일',16],['method','결제방식',14],['status','납부 상태',15],['memo','비고',36],
] as const;
export type ColumnKey = typeof exportColumns[number][0];
export const defaultColumns:ColumnKey[]=exportColumns.map(c=>c[0]).filter(c=>c!=='classes'&&c!=='memo');
export function monthsBetween(start:string,end:string):string[]{
 if(!/^\d{4}-(0[1-9]|1[0-2])$/.test(start)||!/^\d{4}-(0[1-9]|1[0-2])$/.test(end)||start>end)return [];
 const a=Number(start.slice(0,4))*12+Number(start.slice(5))-1,b=Number(end.slice(0,4))*12+Number(end.slice(5))-1;
 if(b-a>23)return [];
 return Array.from({length:b-a+1},(_,i)=>`${Math.floor((a+i)/12)}-${String((a+i)%12+1).padStart(2,'0')}`);
}
export function koreaDate(value:string):string {
 const d=new Date(value);if(!Number.isFinite(d.getTime()))return '';
 return new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(d);
}
export function excelDate(value:string):number|null {
 const day=koreaDate(value);return day?Date.parse(`${day}T00:00:00Z`)/86400000+25569:null;
}
export function amounts(row:ExportCharge){
 const unpaid=Math.max(row.totalAmount-row.paidAmount,0);
 return {total:row.totalAmount,paid:row.paidAmount,waived:row.status==='waived'?unpaid:0,balance:row.status==='waived'?0:unpaid};
}
export const paymentMethod=(method:string)=>({card:'카드',cash:'현금',transfer:'계좌이체',siru:'시루',other:'기타'}[method]??method);
export function paymentRows(row:ExportEntry){return row.payments.length?[...row.payments].sort((a,b)=>a.paidAt.localeCompare(b.paidAt)): [null];}
export function exportValue(row:ExportEntry,key:ColumnKey,payment:ExportCharge['payments'][number]|null,first=true):string|number|null {
 const sums=amounts(row);
 switch(key){
 case 'studentName':return row.studentName;case 'school':return row.school||'미등록';case 'grade':return row.grade||'미등록';
 case 'subjects':return [...new Set((row.lineItems??[]).map(i=>i.className))].join(', ')||(row.subjects??[]).join(', ');
 case 'classes':return (row.classNames??[]).join(', ');
 case 'total':case 'waived':case 'balance':return first?sums[key]:null;
 case 'paid':return payment?.amount??(first?row.paidAmount:null);
 case 'date':return payment?excelDate(payment.paidAt):null;
 case 'method':return payment?paymentMethod(payment.method):'—';
 case 'status':return statusLabels[row.status];case 'memo':return row.memo??'';
 }
}
export type ExportFilters={query:string;school:string;grade:string;subject:string;status:string};
export function matchesExport(row:ExportEntry,f:ExportFilters){return (!f.school||(row.school||'학교 미등록')===f.school)&&(!f.grade||(row.grade||'학년 미등록')===f.grade)&&(!f.subject||(row.subjects??[]).includes(f.subject))&&(!f.status||row.status===f.status)&&(!f.query||[row.studentName,row.school,row.grade,row.memo,...(row.classNames??[])].join(' ').toLocaleLowerCase().includes(f.query.trim().toLocaleLowerCase()));}
