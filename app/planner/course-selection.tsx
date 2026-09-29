"use client";
import { useState } from "react";
import { StudentRoster } from "./student-roster";
import type { Config, Course, Student } from "./engine";
import { MergeEditor } from "./merge-editor";
import { releaseMerge } from "./merge";
import styles from "./planner.module.css";

function gradeOrder(c: Course) {
  const named = c.name.match(/(초|중|고)\s*([1-6])/);
  const grades = named ? [named] : c.students.map(s => s.grade.match(/(초|중|고)\s*([1-6])/)).filter(Boolean);
  return grades.length ? Math.min(...grades.map(g => ({초:0,중:10,고:20}[g![1] as "초"|"중"|"고"] + Number(g![2])))) : 99;
}
const high3 = (c: Course) => /고\s*3/.test(c.name) || (c.students.length > 0 && c.students.every(s => /고\s*3/.test(s.grade)));

export function CourseSelection({config, onChange, selectedStudent, onSelectStudent}: {config: Config; onChange: (next: Config) => void; selectedStudent?: string; onSelectStudent: (student: Student) => void}) {
  const [mergeEditor, setMergeEditor] = useState<Course | null | undefined>(undefined);
  const [query, setQuery] = useState("");
  const [subject, setSubject] = useState("");
  const [teacher, setTeacher] = useState("");
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});
  const subjects = [...new Set(config.courses.map(c => c.subject || "미분류"))].sort((a,b) => {
    const rank = (s: string) => ({영어:0,수학:1,국어:2}[s] ?? 3);
    return rank(a)-rank(b) || a.localeCompare(b,"ko");
  });
  const matches = (c: Course) => (!teacher || c.teachers.includes(teacher)) && (!query.trim() || c.name.replace(/\s/g,"").toLowerCase().includes(query.replace(/\s/g,"").toLowerCase()));
  const patch = (ids: string[], values: Partial<Course>) => {
    const targets = new Set(ids);
    onChange({...config, courses:config.courses.map(c => targets.has(c.id) ? {...c,...values} : c)});
  };
  const groups = subjects.filter(s => !subject || s===subject).map(s => ({subject:s, rows:config.courses.filter(c=>(c.subject||"미분류")===s&&matches(c)).sort((a,b)=>gradeOrder(a)-gradeOrder(b)||a.name.localeCompare(b.name,"ko",{numeric:true}))})).filter(g=>g.rows.length);
  return <>
    <div className={styles.mergeToolbar}><button type="button" onClick={()=>setMergeEditor(null)}>＋ 합반 만들기</button><span>실제 클래스는 유지하고 이 초안에서만 합반합니다.</span></div>
    {mergeEditor!==undefined&&<MergeEditor config={config} existing={mergeEditor??undefined} onClose={()=>setMergeEditor(undefined)} onSave={next=>{onChange(next);setMergeEditor(undefined);}}/>}
    <div className={styles.courseFilters}>
      <label>클래스 검색<input type="search" placeholder="클래스 이름 검색" value={query} onChange={e=>setQuery(e.target.value)}/></label>
      <label>담당 선생님<select value={teacher} onChange={e=>setTeacher(e.target.value)}><option value="">전체 선생님</option>{config.teachers.map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select></label>
    </div>
    <div className={styles.subjectTabs} aria-label="과목 필터">{["",...subjects].map(s=><button type="button" key={s} aria-pressed={subject===s} onClick={()=>setSubject(s)}>{s||"전체"}</button>)}<button type="button" onClick={()=>patch(config.courses.filter(high3).map(c=>c.id),{enabled:false})}>고3 전체 제외</button></div>
    <p className={styles.selectionHint}>필터는 보기만 바꿉니다. 전체 {config.courses.filter(c=>c.enabled).length}개 선택 클래스가 함께 편성됩니다.</p>
    {groups.map(group=>{
      const selected=group.rows.filter(c=>c.enabled);
      const all=config.courses.filter(c=>(c.subject||"미분류")===group.subject);
      return <section className={styles.subjectGroup} key={group.subject}>
        <div className={styles.groupHead}><button type="button" aria-expanded={!collapsed[group.subject]} onClick={()=>setCollapsed(v=>({...v,[group.subject]:!v[group.subject]}))}><b>{group.subject}</b><span>{all.length}개 중 {all.filter(c=>c.enabled).length}개 선택</span><span aria-hidden="true">{collapsed[group.subject]?"＋":"−"}</span></button></div>
        {!collapsed[group.subject] && <>
          <div className={styles.groupTools}>
            <button type="button" onClick={()=>patch(group.rows.map(c=>c.id),{enabled:selected.length!==group.rows.length})}>{selected.length===group.rows.length?"목록 전체 해제":"목록 전체 선택"}</button>
            <span>표시된 선택 {selected.length}개에 적용</span>
            <label><span className={styles.srOnly}>{group.subject} 선택 클래스 주 횟수 일괄 변경</span><select value="" disabled={!selected.length} onChange={e=>patch(selected.map(c=>c.id),{count:Number(e.target.value)})}><option value="">주 횟수 일괄</option>{[1,2,3,4,5,6].map(n=><option key={n} value={n}>주 {n}회</option>)}</select></label>
            <label><span className={styles.srOnly}>{group.subject} 선택 클래스 수업 길이 일괄 변경</span><select value="" disabled={!selected.length} onChange={e=>patch(selected.map(c=>c.id),{duration:Number(e.target.value)})}><option value="">수업 길이 일괄</option>{[60,90,120,150,180].map(n=><option key={n} value={n}>{n}분</option>)}</select></label>
          </div>
          {group.rows.map(c=><div key={c.id} className={`${styles.course} ${!c.enabled?styles.courseExcluded:""} ${c.students.some(s=>s.id===selectedStudent)?styles.studentMatch:""}`}>
            <label className={styles.courseName}><input type="checkbox" checked={c.enabled} onChange={e=>patch([c.id],{enabled:e.target.checked})}/><span><b>{c.name}{c.memberCourses?.length?" · 합반":""}</b><small>{c.students.length?`${c.students.length}명`:"수강생 없음"} · {c.teachers.map(id=>config.teachers.find(t=>t.id===id)?.name).filter(Boolean).join(", ")||"담당 미지정"}</small></span></label>
            <label>주 횟수<select aria-label={`${c.name} 주 횟수`} value={c.count} onChange={e=>patch([c.id],{count:Number(e.target.value)})}>{[1,2,3,4,5,6].map(n=><option key={n} value={n}>{n}회</option>)}</select></label>
            <label>수업 길이<select aria-label={`${c.name} 수업 길이`} value={c.duration} onChange={e=>patch([c.id],{duration:Number(e.target.value)})}>{[60,90,120,150,180].map(n=><option key={n} value={n}>{n}분</option>)}</select></label>
            <div className={styles.courseRoster}><StudentRoster showAll course={c} selected={selectedStudent} onSelect={onSelectStudent}/></div>
            {c.memberCourses?.length?<div className={styles.mergeActions}><small>{c.memberCourses.map(m=>m.name).join(" + ")}</small><button type="button" onClick={()=>setMergeEditor(c)}>구성 수정</button><button type="button" onClick={()=>onChange({...config,courses:releaseMerge(config.courses,c.id)})}>합반 해제</button></div>:null}
          </div>)}
        </>}
      </section>;
    })}
    {!groups.length&&<p className={styles.empty}>조건에 맞는 클래스가 없습니다. <button type="button" onClick={()=>{setQuery("");setTeacher("");setSubject("");}}>필터 초기화</button></p>}
  </>;
}
