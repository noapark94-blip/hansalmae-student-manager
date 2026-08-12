"use client";

import type { CSSProperties } from "react";

export type WeeklyTimetableRow={id:string;weekday:number;startTime:string;endTime:string;className:string;subject:string;color:string;room?:string|null;teachers?:{id:string;name:string}[]};
const days=["월","화","수","목","금","토","일"];
const slots=[["09:30","11:00"],["11:00","12:30"],["12:30","14:00"],["14:00","15:30"],["15:30","17:00"],["17:00","18:30"],["18:30","20:00"],["20:00","21:30"],["21:30","22:00"]];

export function WeeklyTimetable({rows,compact=false,onSelect}:{rows:WeeklyTimetableRow[];compact?:boolean;onSelect?:(row:WeeklyTimetableRow)=>void}){
  return <div className={`weekly-timetable${compact?" compact":""}`}><div className="weekly-timetable-grid"><b className="timetable-corner">시간</b>{days.map(day=><b key={day}>{day}</b>)}{slots.flatMap(([start,end])=>[<strong key={`${start}-label`}>{start}<i>–</i>{end}</strong>,...days.map((day,dayIndex)=><div className="timetable-cell" key={`${day}-${start}`}>{rows.filter(row=>row.weekday===dayIndex+1&&row.startTime.slice(0,5)>=start&&row.startTime.slice(0,5)<end).map(row=><button type="button" key={`${row.id}-${start}`} onClick={()=>onSelect?.(row)} disabled={!onSelect} style={{"--schedule-color":row.color} as CSSProperties}><span>{row.className}</span><small>{row.startTime.slice(0,5)}–{row.endTime.slice(0,5)}</small><em>{row.subject}{row.teachers?.length?` · ${row.teachers.map(item=>item.name).join("·")}`:""}</em></button>)}</div>)])}</div></div>;
}
