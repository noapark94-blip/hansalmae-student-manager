"use client";
import {useState} from "react";
import type {Config,Course} from "./engine";
import {combineCourses,updateMerge} from "./merge";
import styles from "./planner.module.css";
const grade=(c:Course)=>{const m=c.name.match(/(초|중|고)\s*([1-6])/);return m?m[1]+m[2]:[...new Set(c.students.map(s=>s.grade))].join("·")||"학년 미지정";};
export function MergeEditor({config,existing,onSave,onClose}:{config:Config;existing?:Course;onSave:(c:Config)=>void;onClose:()=>void}){
 const available=[...config.courses.filter(c=>!c.memberCourses?.length),...(existing?.memberCourses??[])];
 const subjects=[...new Set(available.map(c=>c.subject))].sort((a,b)=>a.localeCompare(b,"ko"));
 const [subject,setSubject]=useState(existing?.subject??subjects[0]??"");
 const [query,setQuery]=useState("");const[gradeFilter,setGrade]=useState("");const[teacherFilter,setTeacherFilter]=useState("");
 const [ids,setIds]=useState(existing?.memberCourses?.map(c=>c.id)??[]);
 const [name,setName]=useState(existing?.name??"");const[teacher,setTeacher]=useState(existing?.teachers[0]??"");
 const[count,setCount]=useState(existing?.count??(subject.includes("국어")||subject.includes("기하")?2:3));const[duration,setDuration]=useState(existing?.duration??120);const[room,setRoom]=useState(existing?.room??"");const[error,setError]=useState("");
 const members=available.filter(c=>ids.includes(c.id));const students=new Set(members.flatMap(c=>c.students.map(s=>s.id)));
 const rows=available.filter(c=>c.subject===subject&&(!query.trim()||c.name.replace(/\s/g,"").toLowerCase().includes(query.replace(/\s/g,"").toLowerCase()))&&(!gradeFilter||grade(c)===gradeFilter)&&(!teacherFilter||c.teachers.includes(teacherFilter))).sort((a,b)=>grade(a).localeCompare(grade(b),"ko",{numeric:true})||a.name.localeCompare(b.name,"ko"));
 const save=()=>{try{const merged=combineCourses(members,{id:existing?.id??`merge-${crypto.randomUUID()}`,name,teacherId:teacher,count,duration,room});onSave({...config,courses:updateMerge(config.courses,merged,existing?.id)});}catch(e){setError((e as Error).message);}};
 return <div className={styles.backdrop} onMouseDown={e=>{if(e.target===e.currentTarget)onClose();}} onKeyDown={e=>{if(e.key==="Escape")onClose();}}><section className={`${styles.modal} ${styles.mergeModal}`} role="dialog" aria-modal="true" aria-labelledby="merge-title"><header className={styles.sectionHead}><div><h2 id="merge-title">{existing?"합반 구성 수정":"합반 만들기"}</h2><p>이 초안에서만 합반으로 계산합니다.</p></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header>
 <div className={styles.mergeFilters}>
 <label>과목<select value={subject} onChange={e=>{setSubject(e.target.value);setGrade("");}}>{subjects.map(s=><option key={s}>{s}</option>)}</select></label>
 <label>학년<select value={gradeFilter} onChange={e=>setGrade(e.target.value)}><option value="">전체 학년</option>{[...new Set(available.filter(c=>c.subject===subject).map(grade))].sort().map(g=><option key={g}>{g}</option>)}</select></label>
 <label>담당 선생님<select value={teacherFilter} onChange={e=>setTeacherFilter(e.target.value)}><option value="">전체 선생님</option>{config.teachers.map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select></label>
 <label>클래스 검색<input autoFocus type="search" value={query} onChange={e=>setQuery(e.target.value)} placeholder="반 이름 검색"/></label></div>
 <div className={styles.mergeRoster}>{rows.map(c=><label key={c.id}><input type="checkbox" checked={ids.includes(c.id)} disabled={members.length>0&&members[0].subject!==c.subject} onChange={e=>setIds(v=>e.target.checked?[...v,c.id]:v.filter(id=>id!==c.id))}/><span><b>{c.name}</b><small>{grade(c)} · {c.students.length}명 · {c.teachers.map(id=>config.teachers.find(t=>t.id===id)?.name).filter(Boolean).join(", ")||"담당 미지정"}</small></span></label>)}{!rows.length&&<p>조건에 맞는 반이 없습니다.</p>}</div>
 <div className={styles.mergeSelected}><b>선택한 반 {members.length}개 · 학생 {students.size}명</b><p>같은 과목끼리 선택할 수 있습니다. 필터를 바꿔도 선택은 유지됩니다.</p><div>{members.map(c=><button type="button" key={c.id} onClick={()=>setIds(v=>v.filter(id=>id!==c.id))} aria-label={`${c.name} 선택 해제`}>{c.name} ×</button>)}</div></div>
 <div className={styles.mergeFilters}><label>합반 이름<input value={name} maxLength={100} placeholder="예: 고2 영어 합반" onChange={e=>setName(e.target.value)}/></label><label>합반 담당 선생님<select value={teacher} onChange={e=>setTeacher(e.target.value)}><option value="">선생님 선택</option>{config.teachers.map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select></label><label>주 횟수<select value={count} onChange={e=>setCount(+e.target.value)}>{[1,2,3,4,5,6].map(n=><option key={n} value={n}>{n}회</option>)}</select></label><label>수업 길이<select value={duration} onChange={e=>setDuration(+e.target.value)}>{[60,90,120,150,180].map(n=><option key={n} value={n}>{n}분</option>)}</select></label><label>강의실<input value={room} onChange={e=>setRoom(e.target.value)} placeholder="미정이면 비워 두세요"/></label></div>
 {error&&<p className={styles.error}>{error}</p>}<footer><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.primary} disabled={members.length<2||!name.trim()||!teacher} onClick={save}>{existing?"합반 수정":"초안에 합반 추가"}</button></footer></section></div>;
}
