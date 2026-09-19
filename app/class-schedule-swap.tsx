"use client";
import { useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { isSwapScheduleAvailable, previewScheduleSwap, scheduleSwapBase, type SwapSchedule } from "./class-schedule-swap-model";
import styles from "./class-schedule-swap.module.css";
const days = ["월", "화", "수", "목", "금", "토", "일"];
export function ClassScheduleSwap({ supabase, row, schedules, onSaved, onCancel, onBusyChange }: {
  supabase: SupabaseClient; row: SwapSchedule; schedules: SwapSchedule[];
  onSaved: () => Promise<void>; onCancel: () => void; onBusyChange: (busy: boolean) => void;
}) {
  const [targetId, setTargetId] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const busy = useRef(false);
  const candidates = schedules.filter(s => isSwapScheduleAvailable(s) && s.id !== row.id && s.weekday === row.weekday).sort((a,b) => a.startTime.localeCompare(b.startTime) || a.className.localeCompare(b.className));
  const target = candidates.find(s => s.id === targetId);
  const preview = target ? previewScheduleSwap(row, target, schedules) : null;
  const save = async () => {
    if (!target || !preview || preview.error || busy.current) return;
    busy.current = true; setSaving(true); onBusyChange(true); setError("");
    try {
      const { error: failure } = await supabase.rpc("staff_swap_class_schedule_times", {
        p_first_id: row.id, p_second_id: target.id,
        p_first_base: scheduleSwapBase(row), p_second_base: scheduleSwapBase(target),
      });
      if (failure) throw failure;
      await onSaved();
    } catch (failure) { setError((failure as { message?: string }).message || "시간을 맞바꾸지 못했습니다. 다시 시도해 주세요."); }
    finally { busy.current = false; setSaving(false); onBusyChange(false); }
  };
  return <section className={styles.panel} aria-label="수업 시간 맞바꾸기" aria-busy={saving}>
    <div className={styles.heading}><span aria-hidden="true">⇄</span><div><small>{days[row.weekday - 1]}요일 정규 시간표</small><h3>수업 시간 맞바꾸기</h3></div></div>
    <p className={styles.copy}>같은 요일의 두 수업을 한 번에 옮겨요.<br/>각 수업의 길이와 담당 선생님은 유지됩니다.</p>
    <label className={styles.label}>맞바꿀 수업<select value={targetId} disabled={saving} onChange={e => { setTargetId(e.target.value); setError(""); }}><option value="">수업을 선택해 주세요</option>{candidates.map(s => <option key={s.id} value={s.id}>{s.startTime.slice(0,5)}–{s.endTime.slice(0,5)} · {s.className}</option>)}</select></label>
    {!candidates.length && <p className={styles.copy}>같은 요일에 맞바꿀 다른 수업이 없습니다.</p>}
    {target && preview && preview.rows.length > 0 && <div className={styles.preview} aria-label="변경 전후 시간" aria-live="polite">{[row, target].map((s,i) => <div className={styles.row} key={s.id}><strong>{s.className}</strong><div><span>{s.startTime.slice(0,5)}–{s.endTime.slice(0,5)}</span><i aria-hidden="true">→</i><b>{preview.rows[i].startTime}–{preview.rows[i].endTime}</b></div></div>)}</div>}
    <p className={styles.note}>적용 즉시 매주 {days[row.weekday - 1]}요일 정규 배정이 변경됩니다. 다른 요일과 별도로 등록한 날짜별 변경 일정은 유지됩니다.</p>
    {(error || preview?.error) && <p className={styles.error} role="alert">{error || preview?.error}</p>}
    <div className={styles.actions}><button type="button" disabled={saving} onClick={onCancel}>돌아가기</button><button type="button" disabled={saving || !target || Boolean(preview?.error)} onClick={() => void save()}>{saving ? "적용 중…" : "맞바꾸기 적용"}</button></div>
  </section>;
}
