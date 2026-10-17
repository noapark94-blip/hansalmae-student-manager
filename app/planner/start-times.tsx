"use client";
import { useState } from "react";
import { applyStartTimes, generateStartTimes, WEEKDAYS } from "./start-times-model";
import styles from "./start-times.module.css";

export function StartTimes({ value, onChange }: { value: string[]; onChange: (value: string[]) => void }) {
  const [start, setStart] = useState("16:00");
  const [interval, setInterval] = useState(() => {
    try {
      const saved = Number(localStorage.getItem("hsm-planner-time-interval"));
      return saved === 90 || saved === 120 ? saved : 120;
    } catch { return 120; }
  });
  const [selected, setSelected] = useState([0, 2, 4]);
  const [previous, setPrevious] = useState<string[] | null>(null);
  const [notice, setNotice] = useState("");
  const times = generateStartTimes(start, interval);
  function edit(day: number, next: string) {
    setPrevious(null); setNotice("");
    onChange(value.map((v, i) => i === day ? next : v));
  }
  return <div className={styles.root}>
    <p>시작 시간만 정하고, 같은 간격으로 채우세요.</p>
    <div className={styles.generator}>
      <div className={styles.settings}>
        <label>시작 시간<input type="time" aria-label="자동 생성 시작 시간" value={start} onChange={e => { setStart(e.target.value); setNotice(""); }} /></label>
        <div><span className={styles.label}>수업 간격</span><div className={styles.segment}>
          {[90, 120].map(n => <button type="button" key={n} aria-pressed={interval === n} onClick={() => {
            setInterval(n); setNotice("");
            try { localStorage.setItem("hsm-planner-time-interval", String(n)); } catch { /* Optional preference. */ }
          }}>{n === 120 ? "2시간" : "90분"}</button>)}
        </div></div>
      </div>
      <div className={styles.presets}>{[["월·수·금", [0, 2, 4]], ["화·목", [1, 3]], ["토요일", [5]]] .map(([label, indexes]) => <button type="button" key={String(label)} onClick={() => { setSelected(indexes as number[]); setNotice(""); }}>{label as string}</button>)}</div>
      <div className={styles.days} aria-label="시간을 적용할 요일">{WEEKDAYS.map((d, i) => <button type="button" key={d} aria-label={`${d}요일 선택`} aria-pressed={selected.includes(i)} onClick={() => { setSelected(s => s.includes(i) ? s.filter(n => n !== i) : [...s, i]); setNotice(""); }}>{d}</button>)}</div>
      <div className={styles.preview}><span className={styles.label}>생성 미리보기 · 22시 종료 기준</span><div>{times.length ? times.map(t => <span key={t}>{t}</span>) : <small>22시 안에 수업이 끝나는 시작 시간을 입력하세요.</small>}</div></div>
      <button type="button" className={styles.apply} disabled={!times.length || !selected.length} onClick={() => {
        setPrevious([...value]); onChange(applyStartTimes(value, selected, times));
        setNotice(`${WEEKDAYS.filter((_, i) => selected.includes(i)).join("·")}요일에 ${times.length}개 시간을 적용했습니다.`);
      }}>선택 요일에 적용{selected.length > 0 ? ` · ${selected.length}일` : ""}</button>
      <small className={styles.help}>선택한 요일의 시작 시간을 바꿉니다. 클래스별 수업 길이는 별도로 설정하세요.</small>
    </div>
    <div className={styles.feedback} role="status">{notice}{previous && <button type="button" onClick={() => { onChange(previous); setPrevious(null); setNotice("적용 전 시간으로 되돌렸습니다."); }}>되돌리기</button>}</div>
    <div className={styles.schedule}>{WEEKDAYS.map((d, i) => <DayTimes key={d} day={d} value={value[i] || ""} onChange={next => edit(i, next)} />)}</div>
  </div>;
}

function DayTimes({ day, value, onChange }: { day: string; value: string; onChange: (value: string) => void }) {
  const [adding, setAdding] = useState(false);
  const [next, setNext] = useState("");
  const times = value.split(",").map(t => t.trim()).filter(Boolean);
  function update(values: string[]) { onChange([...new Set(values)].sort().join(",")); }
  return <div className={styles.dayRow}>
    <b>{day}</b><div className={styles.dayContent}>
      <div className={styles.chips}>{times.map((t, i) => <span className={styles.chip} key={`${i}-${t}`}>
        <input type="time" value={t} aria-label={`${day}요일 ${i + 1}번째 시작 시간`} onChange={e => { if (e.target.value) update(times.map((v, j) => j === i ? e.target.value : v)); }} />
        <button type="button" aria-label={`${day}요일 ${t} 삭제`} onClick={() => update(times.filter((_, j) => j !== i))}>×</button>
      </span>)}{!times.length && <span className={styles.empty}>수업 없음</span>}
      <button type="button" className={styles.add} aria-label={`${day}요일 시간 추가`} onClick={() => setAdding(v => !v)}>{adding ? "닫기" : "+"}</button></div>
      {adding && <div className={styles.addForm}><input autoFocus type="time" aria-label={`${day}요일 추가할 시간`} value={next} onChange={e => setNext(e.target.value)} /><button type="button" disabled={!next || times.includes(next)} onClick={() => { update([...times, next]); setNext(""); setAdding(false); }}>추가</button></div>}
    </div>
  </div>;
}
