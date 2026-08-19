"use client";

function normalizeMilitaryTime(raw:string){
  const digits=raw.replace(/\D/g,"").slice(0,4);
  if(digits.length<3)return digits;
  return `${digits.slice(0,2)}:${digits.slice(2)}`;
}

export function isMilitaryTime(value:string){
  return /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value);
}

export function MilitaryTimeInput({value,onChange,label="시간"}:{value:string;onChange:(value:string)=>void;label?:string}){
  return <label>{label}<input type="text" inputMode="numeric" autoComplete="off" maxLength={5} value={value} onChange={(event)=>onChange(normalizeMilitaryTime(event.target.value))} placeholder="예: 1730" aria-label={`${label}, 24시간제로 네 자리 입력`}/><small>24시간제 4자리</small></label>;
}
