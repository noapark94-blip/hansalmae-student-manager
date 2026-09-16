export const weekdaySlots=[["14:30","16:00"],["16:00","17:30"],["17:30","19:00"],["19:00","20:30"],["20:30","22:00"]] as const;
export const weekendSlots=[["09:30","11:00"],["11:00","12:30"],["12:30","14:00"],["14:00","15:30"],["15:30","17:00"]] as const;
export const correctionSlots=(weekday:number)=>weekday<=5?weekdaySlots:weekendSlots;
export function correctionBucket(weekday:number,start:string){
 const slots=correctionSlots(weekday),time=start.slice(0,5);
 return [...slots].reverse().find(slot=>time>=slot[0])?.[0]??slots[0][0];
}
export function isStandardCorrectionTime(weekday:number,start:string,end:string){return correctionSlots(weekday).some(slot=>slot[0]===start.slice(0,5)&&slot[1]===end.slice(0,5));}
export function validCorrectionTime(start:string,end:string){return /^([01]\d|2[0-3]):[0-5]\d$/.test(start)&&/^([01]\d|2[0-3]):[0-5]\d$/.test(end)&&start<end;}
export function defaultCorrectionEnd(start:string){
 if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(start))return "";
 const [h,m]=start.split(':').map(Number),total=h*60+m+90;
 return total<1440?`${String(Math.floor(total/60)).padStart(2,'0')}:${String(total%60).padStart(2,'0')}`:"";
}
