export type MakeupMonthItem={recordKind:string;missedDate:string|null;scheduledAt:string|null;status:string|null};
export function koreaMonth(){return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit'}).format(new Date());}
export function shiftMakeupMonth(month:string,delta:number){const [y,m]=month.split('-').map(Number),d=new Date(Date.UTC(y,m-1+delta,1));return d.toISOString().slice(0,7);}
export function makeupDate(item:MakeupMonthItem){if(item.recordKind==='absence')return item.missedDate??'';return item.scheduledAt?new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(item.scheduledAt)):'';}
export function inMakeupScope(item:MakeupMonthItem,month:string,scope:string){
 if(item.status==='cancelled')return false;
 if(scope==='all')return true;
 if(scope==='pending')return item.recordKind==='absence'&&item.status!=='completed'&&Boolean(item.missedDate)&&item.missedDate!<month+'-01';
 return makeupDate(item).slice(0,7)===month;
}
