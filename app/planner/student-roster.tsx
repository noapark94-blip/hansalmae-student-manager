"use client";
import { useState } from "react";
import type { Course, Student } from "./engine";
import styles from "./planner.module.css";

export function StudentRoster({course, selected, onSelect, showAll = false}: {showAll?: boolean; course: Course; selected?: string; onSelect: (student: Student) => void}) {
  const [expanded, setExpanded] = useState(false);
  const students = [...new Map(course.students.map(s => [s.id, s])).values()].sort((a,b) => a.name.localeCompare(b.name, "ko") || a.id.localeCompare(b.id));
  if (!students.length) return null;
  return <div className={styles.roster} aria-label={`${course.name} 수강생`}>
    <div className={styles.rosterNames}>{(expanded || showAll ? students : students.slice(0,3)).map(s => <div key={s.id}>
      <button type="button" aria-pressed={selected === s.id} onClick={() => onSelect(s)} title={`${s.name} ${s.grade} 수업 강조`}>{s.name}</button>
      {expanded && <small>{s.grade}{course.memberCourses?.length ? ` · ${course.memberCourses.filter(c => c.students.some(m => m.id === s.id)).map(c => c.name).join(" · ")}` : ""}</small>}
    </div>)}</div>
    {((!showAll && students.length > 3) || !!course.memberCourses?.length) && <button type="button" className={styles.rosterToggle} aria-expanded={expanded} onClick={() => setExpanded(v => !v)}>{expanded ? "접기" : !showAll && students.length > 3 ? `외 ${students.length - 3}명 보기` : "소속 반 보기"}</button>}
  </div>;
}
