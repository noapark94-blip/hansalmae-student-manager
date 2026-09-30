"use client";
import {useState, useEffect, useRef, type DragEvent} from "react";
import {clock, domains, validate, type Config, type Meeting, type Student} from "./engine";
import {StudentRoster} from "./student-roster";
import styles from "./planner.module.css";
const days=["월","화","수","목","금","토","일"];
export const sameMeeting=(a:Meeting,b:Meeting)=>a.classId===b.classId&&a.day===b.day&&a.start===b.start&&a.end===b.end;
export function PlacementBoard({config,meetings,onChange,teacherFilter,selectedStudent,onSelectStudent,readOnly=false}:{readOnly?:boolean;config:Config;meetings:Meeting[];onChange:(config:Config,meetings:Meeting[])=>void;teacherFilter:string;selectedStudent?:string;onSelectStudent:(student:Student)=>void}) {
 const [picked,setPicked]=useState<{id:string;index:number}|null>(null);
 const dragRef=useRef<{id:string;index:number}|null>(null);
 const [dragging,setDragging]=useState(false);
 const [over,setOver]=useState("");
 function endDrag(){dragRef.current=null;setDragging(false);setOver("");setPicked(null);}
 function startDrag(e:DragEvent<HTMLElement>,id:string,index:number){
  if(readOnly){e.preventDefault();return;}
  const old=index>=0?meetings[index]:null;
  if(old&&(config.fixed||[]).some(f=>sameMeeting(f,old))){e.preventDefault();return;}
  const item={id,index};dragRef.current=item;setPicked(item);setDragging(true);setMessage("");
  e.dataTransfer.effectAllowed="move";e.dataTransfer.setData("text/plain",id);
  e.dataTransfer.setDragImage(e.currentTarget,30,20);
 }
 function unassign(){
  const item=dragRef.current||picked;
  if(readOnly||!item||item.index<0)return;
  const old=meetings[item.index];
  if(!old||fixed.some(f=>sameMeeting(f,old)))return;
  onChange(config,meetings.filter((_,i)=>i!==item.index));endDrag();
 }
 const [message,setMessage]=useState("");
 const [query,setQuery]=useState("");
 const [subject,setSubject]=useState("");
 const [grade,setGrade]=useState("");
 useEffect(()=>{endDrag();},[meetings,config,readOnly]);
 const fixed=config.fixed||[];
 const courses=config.courses.filter(c=>c.enabled);
 const visible=courses.filter(c=>!teacherFilter||c.teachers.includes(teacherFilter));
 const starts=[...new Set(courses.flatMap(c=>domains(c,config).map(s=>s.start)).concat(meetings.map(m=>m.start)))].sort((a,b)=>a-b);
 const duration=new Set(courses.map(c=>c.duration));
 function place(day:number,start:number){
  if(readOnly)return;
  const item=dragRef.current||picked;
  if(!item)return;
  const c=courses.find(c=>c.id===item.id);
  if(!c)return;
  const old=item.index>=0?meetings[item.index]:null;
  if(old&&fixed.some(f=>sameMeeting(f,old))){setMessage("고정을 해제한 뒤 이동해 주세요.");return;}
  const slot=domains(c,config).find(s=>s.day===day&&s.start===start);
  if(!slot){setMessage(`${c.name}: 근무 요일·등원 시간·수업 길이에 맞지 않는 칸입니다.`);return;}
  const next=[...meetings.filter((_,i)=>i!==item.index),{classId:c.id,...slot}];
  const issues=validate({...config,courses:config.courses.map(c=>({...c,count:next.filter(m=>m.classId===c.id).length}))},next);
  if(issues.length){setMessage(issues.join(" · "));return;}
  onChange(config,next);endDrag();setMessage("배정했습니다. 추천에서도 유지할 수업은 고정해 주세요.");
 }
 function evaluateReason(day:number,start:number){
  if(!picked)return "";
  const c=courses.find(c=>c.id===picked.id);
  if(!c)return "클래스를 다시 선택해 주세요.";
  const slot=domains(c,config).find(s=>s.day===day&&s.start===start);
  if(!slot)return "근무 요일 또는 등원 시간에 맞지 않습니다.";
  const rows=[...meetings.filter((_,i)=>i!==picked.index),{classId:c.id,...slot}];
  return validate({...config,courses:config.courses.map(c=>({...c,count:rows.filter(m=>m.classId===c.id).length}))},rows).join(" · ");
 }
 const cellReasons=new Map(starts.flatMap(start=>days.map((_,i)=>[`${i+1}:${start}`,picked&&!readOnly?evaluateReason(i+1,start):""] as const)));
 const reason=(day:number,start:number)=>cellReasons.get(`${day}:${start}`)||"";
 const unassigned=visible.filter(c=>c.count>meetings.filter(m=>m.classId===c.id).length&&(!subject||c.subject===subject)&&(!grade||c.students.some(s=>s.grade===grade))&&(!query||[c.name,...c.students.map(s=>s.name),...c.teachers.map(id=>config.teachers.find(t=>t.id===id)?.name||"")].join(" ").toLowerCase().includes(query.toLowerCase())));
 return <div>
 {!readOnly&&<p className={styles.boardHint}>블록을 끌어 배정·이동하고, 왼쪽 미배정 영역으로 끌어 빼세요. 추천에서도 유지할 수업만 고정하세요.</p>}
 {message&&<p role="status" className={styles.notice}>{message}</p>}
 {picked&&!readOnly&&!dragging&&<div className={styles.studentFocus}><span>{courses.find(c=>c.id===picked.id)?.name} · 배정할 칸을 선택하세요</span><button type="button" onClick={()=>setPicked(null)}>선택 취소</button></div>}
 <div className={readOnly?undefined:styles.boardLayout}>
 {!readOnly&&<aside className={styles.classShelf} data-drop-active={dragging&&picked?.index!==-1} data-drag-over={over==="shelf"} onDragOver={e=>{if(dragRef.current&&dragRef.current.index>=0){e.preventDefault();e.dataTransfer.dropEffect="move";setOver("shelf");}}} onDragLeave={e=>{if(!e.currentTarget.contains(e.relatedTarget as Node|null))setOver("");}} onDrop={e=>{e.preventDefault();unassign();}}>
 {dragging&&picked&&picked.index>=0&&<div className={styles.returnZone}>여기에 놓으면 배정 해제</div>}
 <header><b>미배정 클래스</b><small>{unassigned.length}개 반</small></header>
 <input aria-label="클래스 또는 학생 검색" placeholder="반 · 학생 · 선생님 검색" value={query} onChange={e=>setQuery(e.target.value)}/>
 <div className={styles.shelfFilters}><select aria-label="미배정 과목" value={subject} onChange={e=>setSubject(e.target.value)}><option value="">전체 과목</option>{[...new Set(courses.map(c=>c.subject))].sort().map(s=><option key={s}>{s}</option>)}</select><select aria-label="미배정 학년" value={grade} onChange={e=>setGrade(e.target.value)}><option value="">전체 학년</option>{[...new Set(courses.flatMap(c=>c.students.map(s=>s.grade)))].sort().map(g=><option key={g}>{g}</option>)}</select></div>
 <div className={styles.shelfList}>{unassigned.map(c=><article key={c.id} className={styles.shelfCard} data-selected={picked?.id===c.id} draggable onDragStart={e=>startDrag(e,c.id,-1)} onDragEnd={endDrag}>
 <button type="button" onClick={()=>setPicked({id:c.id,index:-1})}><span className={styles.shelfTitle}><b>{c.name}</b><span className={styles.remainingCount}>미배정 {c.count-meetings.filter(m=>m.classId===c.id).length}회</span></span><small>{c.teachers.map(id=>config.teachers.find(t=>t.id===id)?.name).join(" · ")} · {c.duration}분 · {new Set(c.students.map(s=>s.id)).size}명</small></button>
 <StudentRoster showAll course={c} selected={selectedStudent} onSelect={onSelectStudent}/></article>)}{!unassigned.length&&<p>미배정 클래스가 없습니다.</p>}</div>
 </aside>}
 <div className={styles.placementScroll}><table className={styles.placementTable}><thead><tr><th>시간</th>{days.map(d=><th key={d}>{d}</th>)}</tr></thead><tbody>{starts.map(start=><tr key={start}><th scope="row">{clock(start)}{duration.size===1&&<><br/>–{clock(start+[...duration][0])}</>}</th>{days.map((d,di)=><td key={d} data-available={picked&&!readOnly?!reason(di+1,start):undefined} data-drag-over={over===`${di+1}:${start}`} title={picked?reason(di+1,start):undefined} onDragOver={e=>{if(dragRef.current&&!readOnly){e.preventDefault();e.dataTransfer.dropEffect=reason(di+1,start)?"none":"move";setOver(`${di+1}:${start}`);}}} onDragLeave={e=>{if(!e.currentTarget.contains(e.relatedTarget as Node|null))setOver("");}} onDrop={e=>{e.preventDefault();place(di+1,start);endDrag();}}>
 {meetings.map((m,index)=>({m,index})).filter(({m})=>m.day===di+1&&m.start===start&&visible.some(c=>c.id===m.classId)).map(({m,index})=>{const c=courses.find(c=>c.id===m.classId)!;const locked=fixed.some(f=>sameMeeting(f,m));return <article key={`${c.id}-${index}`} className={`${styles.placementLesson} ${c.students.some(s=>s.id===selectedStudent)?styles.studentMatch:""}`} draggable={!locked&&!readOnly} onDragStart={e=>startDrag(e,c.id,index)} onDragEnd={endDrag}>
 <b>{c.name}</b>{duration.size>1&&<small>{c.duration}분 · {clock(m.end)} 종료</small>}<small>{c.teachers.map(id=>config.teachers.find(t=>t.id===id)?.name).join("·")}{c.room?` · ${c.room}`:""}</small><StudentRoster showAll course={c} selected={selectedStudent} onSelect={onSelectStudent}/>
 {!readOnly&&<div><button type="button" aria-pressed={locked} onClick={()=>onChange({...config,fixed:locked?fixed.filter(f=>!sameMeeting(f,m)):[...fixed,m]},meetings)}>{locked?"고정됨 · 해제":"고정"}</button><button type="button" disabled={locked} onClick={()=>setPicked({id:c.id,index})}>이동</button><button type="button" disabled={locked} onClick={()=>onChange(config,meetings.filter((_,i)=>i!==index))}>배정 해제</button></div>}</article>;})}
 {picked&&!readOnly&&!dragging&&<button type="button" className={styles.placeHere} title={reason(di+1,start)||"배정 가능"} aria-disabled={!!reason(di+1,start)} onClick={()=>{const why=reason(di+1,start);if(why)setMessage(why);else place(di+1,start);}}>{reason(di+1,start)?"배정 불가 · 이유":"여기에 배정"}</button>}
 </td>)}</tr>)}</tbody></table></div></div></div>;
}
