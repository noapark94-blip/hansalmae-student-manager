"use client";

import { useState, type CSSProperties } from "react";

export type WeeklyTimetableRow={id:string;weekday:number;startTime:string;endTime:string;className:string;subject:string;color:string;room?:string|null;teachers?:{id:string;name:string}[]};
const days=["월","화","수","목","금","토","일"];
const slots=[["09:30","11:00"],["11:00","12:30"],["12:30","14:00"],["14:00","15:30"],["15:30","17:00"],["17:00","18:30"],["18:30","20:00"],["20:00","21:30"],["21:30","22:00"]];
const COLLAPSED_LIMIT=4;

export function WeeklyTimetable({rows,compact=false,onSelect}:{rows:WeeklyTimetableRow[];compact?:boolean;onSelect?:(row:WeeklyTimetableRow)=>void}){
  const [expandedCells,setExpandedCells]=useState<Record<string,boolean>>({});
  return <div className={`weekly-timetable${compact?" compact":""}`}><div className="weekly-timetable-grid"><b className="timetable-corner">시간</b>{days.map(day=><b key={day}>{day}</b>)}{slots.flatMap(([start,end])=>[<strong key={`${start}-label`}>{start}<i>–</i>{end}</strong>,...days.map((day,dayIndex)=>{
    const cellKey=`${dayIndex+1}-${start}`;
    const cellRows=rows.filter(row=>row.weekday===dayIndex+1&&row.startTime.slice(0,5)>=start&&row.startTime.slice(0,5)<end).sort(compareRows);
    const expanded=!!expandedCells[cellKey];
    const visibleRows=expanded?cellRows:cellRows.slice(0,COLLAPSED_LIMIT);
    const hiddenCount=Math.max(0,cellRows.length-visibleRows.length);
    return <div className={`timetable-cell${cellRows.length>1?" timetable-cell-multi":""}`} key={`${day}-${start}`}>
      <div className="timetable-cell-cards">
        {visibleRows.map(row=><button type="button" key={`${row.id}-${start}`} onClick={()=>onSelect?.(row)} disabled={!onSelect} style={{"--schedule-color":row.color} as CSSProperties}><span>{row.className}</span><small>{row.startTime.slice(0,5)}–{row.endTime.slice(0,5)}</small><em>{row.subject}{row.teachers?.length?` · ${row.teachers.map(item=>item.name).join("·")}`:""}</em></button>)}
      </div>
      {hiddenCount>0&&<button type="button" className="timetable-more" onClick={()=>setExpandedCells(current=>({...current,[cellKey]:true}))}>+{hiddenCount}개 더보기</button>}
      {expanded&&cellRows.length>COLLAPSED_LIMIT&&<button type="button" className="timetable-more timetable-collapse" onClick={()=>setExpandedCells(current=>({...current,[cellKey]:false}))}>접기</button>}
    </div>;
  })])}</div></div>;
}

export function StudentRelevantTimetable({rows}:{rows:WeeklyTimetableRow[]}){
  const visibleDays=days.map((label,index)=>({label,weekday:index+1,rows:rows.filter((row)=>row.weekday===index+1).sort(compareRows)})).filter((day)=>day.rows.length>0);
  if(!visibleDays.length)return <p className="student-hub-empty">배정된 수업 시간이 없습니다.</p>;
  return <div className="student-relevant-timetable">{visibleDays.map((day)=><section key={day.weekday}><h4>{day.label}요일</h4><div>{day.rows.map((row)=><article key={`${row.id}-${row.weekday}`} style={{"--schedule-color":row.color} as CSSProperties}><time>{row.startTime.slice(0,5)}–{row.endTime.slice(0,5)}</time><span><b>{row.className}</b><small>{row.subject}{row.room?` · ${row.room}`:""}{row.teachers?.length?` · ${row.teachers.map((teacher)=>teacher.name).join("·")}`:""}</small></span></article>)}</div></section>)}</div>;
}

function compareRows(left:WeeklyTimetableRow,right:WeeklyTimetableRow){return left.startTime.localeCompare(right.startTime)||left.subject.localeCompare(right.subject,"ko")||left.className.localeCompare(right.className,"ko")}
