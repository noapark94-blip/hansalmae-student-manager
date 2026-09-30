"use client";
import {useState} from "react";
import {clock, domains, validate, type Config, type Meeting, type Student} from "./engine";
import {StudentRoster} from "./student-roster";
import styles from "./planner.module.css";
const days=["월","화","수","목","금","토","일"];
export const sameMeeting=(a:Meeting,b:Meeting)=>a.classId===b.classId&&a.day===b.day&&a.start===b.start&&a.end===b.end;
export function PlacementBoard({config,meetings,onChange,teacherFilter,selectedStudent,onSelectStudent}:{config:Config;meetings:Meeting[];onChange:(config:Config,meetings:Meeting[])=>void;teacherFilter:string;selectedStudent?:string;onSelectStudent:(student:Student)=>void}) {
 const [picked,setPicked]=useState<{id:string;index:number}|null>(null);
 const [message,setMessage]=useState("");
 const fixed=config.fixed||[];
 const courses=config.courses.filter(c=>c.enabled);
 const visible=courses.filter(c=>!teacherFilter||c.teachers.includes(teacherFilter));
 const starts=[...new Set(courses.flatMap(c=>domains(c,config).map(s=>s.start)).concat(meetings.map(m=>m.start)))].sort((a,b)=>a-b);
 const duration=new Set(courses.map(c=>c.duration));
 function place(day:number,start:number){
  if(!picked)return;
  const c=courses.find(c=>c.id===picked.id)!;
  const old=picked.index>=0?meetings[picked.index]:null;
  if(old&&fixed.some(f=>sameMeeting(f,old))){setMessage("고정을 해제한 뒤 이동해 주세요.");return;}
  const slot=domains(c,config).find(s=>s.day===day&&s.start===start);
  if(!slot){setMessage(`${c.name}: 근무 요일·등원 시간·수업 길이에 맞지 않는 칸입니다.`);return;}
  const next=[...meetings.filter((_,i)=>i!==picked.index),{classId:c.id,...slot}];
  const issues=validate({...config,courses:config.courses.map(c=>({...c,count:next.filter(m=>m.classId===c.id).length}))},next);
  if(issues.length){setMessage(issues.join(" · "));return;}
  onChange({...config,fixed:[...fixed,{classId:c.id,...slot}]},next);setPicked(null);setMessage("배정했습니다. 이 수업은 고정되어 다음 추천에서도 유지됩니다.");
 }
 return <div>
 <p className={styles.hint}>블록을 끌거나 ‘이동’을 누른 뒤 시간 칸을 선택하세요. 직접 배정한 수업은 자동 고정됩니다. 이동하려면 먼저 고정을 해제하세요.</p>
 {message&&<p role="status">{message}</p>}
 {picked&&<button type="button" onClick={()=>setPicked(null)}>이동 선택 취소</button>}
 <div className={styles.unassigned}><b>미배정</b>{visible.flatMap(c=>Array.from({length:Math.max(0,c.count-meetings.filter(m=>m.classId===c.id).length)},(_,i)=><button key={`${c.id}-${i}`} type="button" draggable onDragStart={e=>{e.dataTransfer.setData("text/plain",c.id);setPicked({id:c.id,index:-1});}} onClick={()=>setPicked({id:c.id,index:-1})}>{c.name} · {i+1}회차 배정</button>))}</div>
 <div className={styles.placementScroll}><table className={styles.placementTable}><thead><tr><th>시간</th>{days.map(d=><th key={d}>{d}</th>)}</tr></thead><tbody>{starts.map(start=><tr key={start}><th scope="row">{clock(start)}{duration.size===1&&<><br/>–{clock(start+[...duration][0])}</>}</th>{days.map((d,di)=><td key={d} onDragOver={e=>{if(picked)e.preventDefault();}} onDrop={e=>{e.preventDefault();place(di+1,start);}}>
 {meetings.map((m,index)=>({m,index})).filter(({m})=>m.day===di+1&&m.start===start&&visible.some(c=>c.id===m.classId)).map(({m,index})=>{const c=courses.find(c=>c.id===m.classId)!;const locked=fixed.some(f=>sameMeeting(f,m));return <article key={`${c.id}-${index}`} className={`${styles.placementLesson} ${c.students.some(s=>s.id===selectedStudent)?styles.studentMatch:""}`} draggable={!locked} onDragStart={e=>{e.dataTransfer.setData("text/plain",c.id);setPicked({id:c.id,index});}}>
 <b>{c.name}</b>{duration.size>1&&<small>{c.duration}분 · {clock(m.end)} 종료</small>}<small>{c.teachers.map(id=>config.teachers.find(t=>t.id===id)?.name).join("·")}{c.room?` · ${c.room}`:""}</small><StudentRoster showAll course={c} selected={selectedStudent} onSelect={onSelectStudent}/>
 <div><button type="button" aria-pressed={locked} onClick={()=>onChange({...config,fixed:locked?fixed.filter(f=>!sameMeeting(f,m)):[...fixed,m]},meetings)}>{locked?"고정됨 · 해제":"고정"}</button><button type="button" disabled={locked} onClick={()=>setPicked({id:c.id,index})}>이동</button><button type="button" disabled={locked} onClick={()=>onChange(config,meetings.filter((_,i)=>i!==index))}>배정 해제</button></div></article>;})}
 {picked&&<button type="button" className={styles.placeHere} onClick={()=>place(di+1,start)}>여기에 배정</button>}
 </td>)}</tr>)}</tbody></table></div></div>;
}
