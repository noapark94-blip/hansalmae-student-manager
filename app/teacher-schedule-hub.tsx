"use client";

import type { FormEvent, ReactNode } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";

type HubTab = "all" | "teacher" | "correction" | "vehicle";
type Named = { id: string; name: string };
type ClassSchedule = { id: string; classId: string; className: string; subject: string; color: string; weekday: number; startTime: string; endTime: string; room: string | null; teachers: Named[] };
type Correction = { id: string; studentId: string; studentName: string; teacherId: string; teacherName: string; weekday: number; slotIndex: number };
type CorrectionException = { id: string; assignmentId: string; weekStart: string; weekday: number; slotIndex: number; note: string | null };
type VehicleRun = { id: string; managerId: string; managerName: string; weekday: number; pickupTime: string; pickupLocation: string; students: Named[] };
type HubData = { teachers: Named[]; students: Named[]; classes: Named[]; classSchedules: ClassSchedule[]; corrections: Correction[]; correctionExceptions: CorrectionException[]; vehicles: VehicleRun[] };
type Editor = { kind: "class"; row?: ClassSchedule } | { kind: "correction"; row?: Correction } | { kind: "exception"; row: Correction } | { kind: "vehicle"; row?: VehicleRun } | null;

const emptyData: HubData = { teachers: [], students: [], classes: [], classSchedules: [], corrections: [], correctionExceptions: [], vehicles: [] };
const weekdays = ["월", "화", "수", "목", "금", "토"];
const correctionSlots = ["17:30–19:00", "19:00–20:30", "20:30–22:00"];

export function TeacherScheduleHub({ supabase, profile, initialTab }: { supabase: SupabaseClient; profile: Profile; initialTab: HubTab }) {
  const [tab, setTab] = useState<HubTab>(initialTab);
  const [teacherId, setTeacherId] = useState(profile.id);
  const [data, setData] = useState<HubData>(emptyData);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [editor, setEditor] = useState<Editor>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError("");
    const { data: result, error: loadError } = await supabase.rpc("staff_schedule_hub");
    if (loadError || !result) setError("시간표 데이터를 불러오지 못했습니다.");
    else setData({ ...emptyData, ...(result as Partial<HubData>) });
    setLoading(false);
  }, [supabase]);

  useEffect(() => { setTab(initialTab); }, [initialTab]);
  useEffect(() => { void loadData(); }, [loadData]);

  const visibleClasses = useMemo(() => tab === "teacher" ? data.classSchedules.filter((item) => item.teachers.some((teacher) => teacher.id === teacherId)) : data.classSchedules, [data.classSchedules, tab, teacherId]);
  const saved = async () => { setEditor(null); await loadData(); };

  if (loading && data.teachers.length === 0) return <ScheduleMessage text="시간표를 불러오는 중이에요…" />;
  if (error) return <ScheduleMessage text={error} error />;

  return <>
    <div className="page-heading compact"><div><p className="eyebrow">선생님 통합 일정</p><h1>시간표 허브</h1><p>전과목 일정과 개인 배정, 첨삭, 차량 운행을 등록하고 함께 관리합니다.</p></div></div>
    <div className="schedule-tabs" role="tablist">
      <button className={tab === "all" ? "active" : ""} onClick={() => setTab("all")}>전과목 시간표</button>
      <button className={tab === "teacher" ? "active" : ""} onClick={() => setTab("teacher")}>선생님별 시간표</button>
      <button className={tab === "correction" ? "active" : ""} onClick={() => setTab("correction")}>첨삭 시간표</button>
      <button className={tab === "vehicle" ? "active" : ""} onClick={() => setTab("vehicle")}>차량 운행표</button>
    </div>
    {(tab === "all" || tab === "teacher") && <ClassScheduleBoard rows={visibleClasses} teachers={data.teachers} teacherId={teacherId} setTeacherId={setTeacherId} personal={tab === "teacher"} onAdd={() => setEditor({ kind: "class" })} onEdit={(row) => setEditor({ kind: "class", row })} />}
    {tab === "correction" && <CorrectionBoard rows={data.corrections} exceptions={data.correctionExceptions} profile={profile} onAdd={() => setEditor({ kind: "correction" })} onEdit={(row) => setEditor({ kind: "correction", row })} onException={(row) => setEditor({ kind: "exception", row })} />}
    {tab === "vehicle" && <VehicleBoard rows={data.vehicles} onAdd={() => setEditor({ kind: "vehicle" })} onEdit={(row) => setEditor({ kind: "vehicle", row })} />}
    {editor?.kind === "class" && <ClassEditor supabase={supabase} data={data} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind === "correction" && <CorrectionEditor supabase={supabase} data={data} profile={profile} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind === "exception" && <ExceptionEditor supabase={supabase} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind === "vehicle" && <VehicleEditor supabase={supabase} data={data} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
  </>;
}

function ClassScheduleBoard({ rows, teachers, teacherId, setTeacherId, personal, onAdd, onEdit }: { rows: ClassSchedule[]; teachers: Named[]; teacherId: string; setTeacherId: (id: string) => void; personal: boolean; onAdd: () => void; onEdit: (row: ClassSchedule) => void }) {
  return <section className="panel hub-panel"><HubToolbar title={personal ? "선생님별 클래스 배정" : "학원 전과목 시간표"} description="전과목 시간표의 공동담당 배정이 개인 시간표에 자동 반영됩니다."><>{personal && <select value={teacherId} onChange={(event) => setTeacherId(event.target.value)}>{teachers.map((teacher) => <option key={teacher.id} value={teacher.id}>{teacher.name}</option>)}</select>}<button className="primary hub-add" onClick={onAdd}>＋ 수업 배정</button></></HubToolbar><div className="week-column-grid">{weekdays.map((day, index) => <div className="week-column" key={day}><b>{day}</b>{rows.filter((row) => row.weekday === index + 1).map((row) => <button className="schedule-card" key={row.id} onClick={() => onEdit(row)} style={{ borderLeftColor:row.color }}><strong>{row.startTime.slice(0,5)}–{row.endTime.slice(0,5)}</strong><span>{row.className}</span><small>{row.subject}{row.room ? ` · ${row.room}` : ""}</small><em>{row.teachers.map((teacher) => teacher.name).join(" · ") || "담당 미배정"}</em></button>)}</div>)}</div>{rows.length === 0 && <Empty text="등록된 클래스 시간 배정이 없습니다." />}</section>;
}

function CorrectionBoard({ rows, exceptions, profile, onAdd, onEdit, onException }: { rows: Correction[]; exceptions: CorrectionException[]; profile: Profile; onAdd: () => void; onEdit: (row: Correction) => void; onException: (row: Correction) => void }) {
  const upcoming = exceptions.filter((item) => item.weekStart >= getMonday()).slice(0, 6);
  return <section className="panel hub-panel"><HubToolbar title="고정 첨삭 시간표" description="월–금 17:30부터 90분 단위이며, 담당쌤만 자신의 배정을 변경할 수 있습니다."><button className="primary hub-add" onClick={onAdd}>＋ 내 학생 배정</button></HubToolbar>{upcoming.length > 0 && <div className="exception-strip"><b>예정된 주간 변경</b>{upcoming.map((item) => { const assignment = rows.find((row) => row.id === item.assignmentId); return <span key={item.id}>{item.weekStart} · {assignment?.studentName ?? "학생"} → {weekdays[item.weekday - 1]} {correctionSlots[item.slotIndex]}</span>; })}</div>}<div className="correction-grid"><div className="correction-corner">시간</div>{weekdays.slice(0,5).map((day) => <b key={day}>{day}</b>)}{correctionSlots.flatMap((slot, slotIndex) => [<strong key={`${slot}-label`}>{slot}</strong>, ...weekdays.slice(0,5).map((day, dayIndex) => <div key={`${day}-${slot}`} className="correction-cell">{rows.filter((row) => row.weekday === dayIndex + 1 && row.slotIndex === slotIndex).map((row) => <span key={row.id} className={row.teacherId === profile.id ? "editable" : ""}><b>{row.studentName}</b><small>{row.teacherName}쌤</small>{row.teacherId === profile.id && <i><button onClick={() => onEdit(row)}>고정 변경</button><button onClick={() => onException(row)}>이번 주만</button></i>}</span>)}</div>)])}</div>{rows.length === 0 && <Empty text="아직 배정된 고정 첨삭 시간이 없습니다." />}</section>;
}

function VehicleBoard({ rows, onAdd, onEdit }: { rows: VehicleRun[]; onAdd: () => void; onEdit: (row: VehicleRun) => void }) {
  return <section className="panel hub-panel"><HubToolbar title="차량 운행 시간표" description="차량실장님별 탑승 시간·위치·탑승학생을 관리합니다."><button className="primary hub-add" onClick={onAdd}>＋ 운행 등록</button></HubToolbar><div className="vehicle-week">{weekdays.map((day, index) => <div key={day}><b>{day}</b>{rows.filter((row) => row.weekday === index + 1).map((row) => <button className="vehicle-card" key={row.id} onClick={() => onEdit(row)}><time>{row.pickupTime.slice(0,5)}</time><span><strong>{row.pickupLocation}</strong><small>차량실장님 · {row.managerName}</small><em>{row.students.map((student) => student.name).join(", ") || "탑승학생 미배정"}</em></span></button>)}</div>)}</div>{rows.length === 0 && <Empty text="아직 등록된 차량 운행 일정이 없습니다." />}</section>;
}

function ClassEditor({ supabase, data, row, onClose, onSaved }: EditorProps & { data: HubData; row?: ClassSchedule }) {
  const [classId, setClassId] = useState(row?.classId ?? data.classes[0]?.id ?? "");
  const [weekday, setWeekday] = useState(row?.weekday ?? 1);
  const [startTime, setStartTime] = useState(row?.startTime.slice(0,5) ?? "17:30");
  const [endTime, setEndTime] = useState(row?.endTime.slice(0,5) ?? "19:00");
  const [teacherIds, setTeacherIds] = useState(row?.teachers.map((item) => item.id) ?? []);
  const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  useEffect(() => { if (!row) setTeacherIds(data.classSchedules.find((item) => item.classId === classId)?.teachers.map((item) => item.id) ?? []); }, [classId, data.classSchedules, row]);
  const submit = async (event: FormEvent) => { event.preventDefault(); if (!classId || teacherIds.length === 0) return setError("클래스와 담당 선생님을 한 명 이상 선택해 주세요."); setSaving(true); const payload = { class_id: classId, weekday, start_time: startTime, end_time: endTime }; const scheduleResult = row ? await supabase.from("class_schedules").update(payload).eq("id", row.id) : await supabase.from("class_schedules").insert(payload); if (scheduleResult.error) { setError("수업 배정을 저장하지 못했습니다."); setSaving(false); return; } const removed = await supabase.from("class_teachers").delete().eq("class_id", classId); if (removed.error) { setError("공동담당 정보를 저장하지 못했습니다."); setSaving(false); return; } const added = await supabase.from("class_teachers").insert(teacherIds.map((profile_id) => ({ class_id: classId, profile_id }))); if (added.error) { setError("공동담당 정보를 저장하지 못했습니다."); setSaving(false); return; } await onSaved(); };
  const remove = async () => { if (!row || !confirm("이 수업 시간 배정을 삭제할까요?")) return; setSaving(true); const { error: deleteError } = await supabase.from("class_schedules").delete().eq("id", row.id); if (deleteError) { setError("수업 배정을 삭제하지 못했습니다."); setSaving(false); } else await onSaved(); };
  return <EditorModal title={row ? "수업 배정 수정" : "수업 배정 등록"} description="공동담당 선생님은 모두 개인 시간표에 자동 표시됩니다." onClose={onClose}><form onSubmit={submit}><FormSelect label="클래스" value={classId} onChange={setClassId} options={data.classes} disabled={Boolean(row)} /><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={6} /><FormField label="시작 시간"><input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} required /></FormField><FormField label="종료 시간"><input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} required /></FormField></div><CheckList label="공동담당 선생님" rows={data.teachers} selected={teacherIds} onChange={setTeacherIds} />{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} editing={Boolean(row)} onDelete={remove} /></form></EditorModal>;
}

function CorrectionEditor({ supabase, data, profile, row, onClose, onSaved }: EditorProps & { data: HubData; profile: Profile; row?: Correction }) {
  const [studentId, setStudentId] = useState(row?.studentId ?? data.students[0]?.id ?? ""); const [weekday, setWeekday] = useState(row?.weekday ?? 1); const [slotIndex, setSlotIndex] = useState(row?.slotIndex ?? 0); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const submit = async (event: FormEvent) => { event.preventDefault(); setSaving(true); const payload = { student_id: studentId, teacher_profile_id: profile.id, weekday, slot_index: slotIndex }; const result = row ? await supabase.from("correction_assignments").update(payload).eq("id", row.id) : await supabase.from("correction_assignments").insert(payload); if (result.error) { setError("첨삭 배정을 저장하지 못했습니다. 본인 담당 배정인지 확인해 주세요."); setSaving(false); } else await onSaved(); };
  const remove = async () => { if (!row || !confirm("이 학생의 고정 첨삭 배정을 삭제할까요?")) return; setSaving(true); const { error: deleteError } = await supabase.from("correction_assignments").delete().eq("id", row.id); if (deleteError) { setError("첨삭 배정을 삭제하지 못했습니다."); setSaving(false); } else await onSaved(); };
  return <EditorModal title={row ? "고정 첨삭 변경" : "내 학생 첨삭 배정"} description={`${profile.display_name} 선생님 담당으로 저장됩니다.`} onClose={onClose}><form onSubmit={submit}><FormSelect label="학생" value={studentId} onChange={setStudentId} options={data.students} /><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={5} /><SlotSelect value={slotIndex} onChange={setSlotIndex} /></div>{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} editing={Boolean(row)} onDelete={remove} /></form></EditorModal>;
}

function ExceptionEditor({ supabase, row, onClose, onSaved }: EditorProps & { row: Correction }) {
  const [weekStart, setWeekStart] = useState(getMonday()); const [weekday, setWeekday] = useState(row.weekday); const [slotIndex, setSlotIndex] = useState(row.slotIndex); const [note, setNote] = useState(""); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const submit = async (event: FormEvent) => { event.preventDefault(); setSaving(true); const { error: saveError } = await supabase.from("correction_exceptions").upsert({ assignment_id: row.id, week_start: weekStart, weekday, slot_index: slotIndex, note: note.trim() || null }, { onConflict: "assignment_id,week_start" }); if (saveError) { setError("이번 주 변경을 저장하지 못했습니다. 담당 선생님만 변경할 수 있습니다."); setSaving(false); } else await onSaved(); };
  return <EditorModal title="이번 주만 시간 변경" description={`${row.studentName} 학생의 고정 시간은 유지되고 선택한 주에만 적용됩니다.`} onClose={onClose}><form onSubmit={submit}><FormField label="변경할 주의 월요일"><input type="date" value={weekStart} onChange={(e) => setWeekStart(e.target.value)} required /></FormField><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={5} /><SlotSelect value={slotIndex} onChange={setSlotIndex} /></div><FormField label="변경 메모"><input value={note} onChange={(e) => setNote(e.target.value)} placeholder="예: 학교 행사로 목요일 변경" /></FormField>{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} /></form></EditorModal>;
}

function VehicleEditor({ supabase, data, row, onClose, onSaved }: EditorProps & { data: HubData; row?: VehicleRun }) {
  const [managerId, setManagerId] = useState(row?.managerId ?? data.teachers[0]?.id ?? ""); const [weekday, setWeekday] = useState(row?.weekday ?? 1); const [pickupTime, setPickupTime] = useState(row?.pickupTime.slice(0,5) ?? "17:00"); const [location, setLocation] = useState(row?.pickupLocation ?? ""); const [studentIds, setStudentIds] = useState(row?.students.map((item) => item.id) ?? []); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const submit = async (event: FormEvent) => { event.preventDefault(); if (!managerId || !location.trim()) return setError("차량실장님과 탑승 위치를 입력해 주세요."); setSaving(true); const payload = { manager_profile_id: managerId, weekday, pickup_time: pickupTime, pickup_location: location.trim(), active: true }; let runId = row?.id; if (row) { const result = await supabase.from("vehicle_runs").update(payload).eq("id", row.id); if (result.error) return fail("운행 정보를 저장하지 못했습니다."); } else { const result = await supabase.from("vehicle_runs").insert(payload).select("id").single(); if (result.error || !result.data) return fail("운행 정보를 저장하지 못했습니다."); runId = result.data.id; } const removed = await supabase.from("vehicle_boardings").delete().eq("run_id", runId!); if (removed.error) return fail("탑승학생 정보를 저장하지 못했습니다."); if (studentIds.length) { const added = await supabase.from("vehicle_boardings").insert(studentIds.map((student_id) => ({ run_id: runId!, student_id }))); if (added.error) return fail("탑승학생 정보를 저장하지 못했습니다."); } await onSaved(); };
  const fail = (message: string) => { setError(message); setSaving(false); };
  const remove = async () => { if (!row || !confirm("이 차량 운행 일정을 삭제할까요?")) return; setSaving(true); const { error: deleteError } = await supabase.from("vehicle_runs").delete().eq("id", row.id); if (deleteError) fail("운행 일정을 삭제하지 못했습니다."); else await onSaved(); };
  return <EditorModal title={row ? "차량 운행 수정" : "차량 운행 등록"} description="로그인 계정이 있는 교직원만 차량실장님으로 선택할 수 있습니다." onClose={onClose}><form onSubmit={submit}><FormSelect label="차량실장님" value={managerId} onChange={setManagerId} options={data.teachers} /><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={6} /><FormField label="탑승 시간"><input type="time" value={pickupTime} onChange={(e) => setPickupTime(e.target.value)} required /></FormField></div><FormField label="탑승 위치"><input value={location} onChange={(e) => setLocation(e.target.value)} placeholder="예: 배곧중학교 정문" required /></FormField><CheckList label="탑승학생" rows={data.students} selected={studentIds} onChange={setStudentIds} />{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} editing={Boolean(row)} onDelete={remove} /></form></EditorModal>;
}

type EditorProps = { supabase: SupabaseClient; onClose: () => void; onSaved: () => Promise<void> };
function EditorModal({ title, description, onClose, children }: { title: string; description: string; onClose: () => void; children: ReactNode }) { return <div className="modal-backdrop"><section className="student-modal schedule-editor"><header><div><p className="eyebrow">시간표 관리</p><h2>{title}</h2><span>{description}</span></div><button onClick={onClose} aria-label="닫기">×</button></header>{children}</section></div>; }
function HubToolbar({ title, description, children }: { title: string; description: string; children: ReactNode }) { return <div className="hub-toolbar"><div><h2>{title}</h2><span>{description}</span></div><aside>{children}</aside></div>; }
function FormField({ label, children }: { label: string; children: ReactNode }) { return <label className="editor-field"><b>{label}</b>{children}</label>; }
function FormSelect({ label, value, onChange, options, disabled = false }: { label: string; value: string; onChange: (value: string) => void; options: Named[]; disabled?: boolean }) { return <FormField label={label}><select value={value} onChange={(e) => onChange(e.target.value)} disabled={disabled}>{options.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></FormField>; }
function DaySelect({ value, onChange, count }: { value: number; onChange: (value: number) => void; count: number }) { return <FormField label="요일"><select value={value} onChange={(e) => onChange(Number(e.target.value))}>{weekdays.slice(0,count).map((day, index) => <option value={index + 1} key={day}>{day}요일</option>)}</select></FormField>; }
function SlotSelect({ value, onChange }: { value: number; onChange: (value: number) => void }) { return <FormField label="첨삭 시간"><select value={value} onChange={(e) => onChange(Number(e.target.value))}>{correctionSlots.map((slot, index) => <option key={slot} value={index}>{slot}</option>)}</select></FormField>; }
function CheckList({ label, rows, selected, onChange }: { label: string; rows: Named[]; selected: string[]; onChange: (ids: string[]) => void }) { const toggle = (id: string) => onChange(selected.includes(id) ? selected.filter((item) => item !== id) : [...selected, id]); return <fieldset className="editor-checklist"><legend>{label}</legend><div>{rows.map((row) => <label key={row.id}><input type="checkbox" checked={selected.includes(row.id)} onChange={() => toggle(row.id)} />{row.name}</label>)}</div></fieldset>; }
function EditorFooter({ saving, editing = false, onDelete }: { saving: boolean; editing?: boolean; onDelete?: () => void }) { return <footer>{editing && onDelete && <button className="danger-link" type="button" onClick={onDelete}>삭제</button>}<button className="primary" disabled={saving}>{saving ? "저장 중…" : "저장"}</button></footer>; }
function getMonday() { const date = new Date(); const day = date.getDay(); date.setDate(date.getDate() - (day === 0 ? 6 : day - 1)); return date.toISOString().slice(0,10); }
function Empty({ text }: { text: string }) { return <p className="hub-empty">{text}</p>; }
function ScheduleMessage({ text, error = false }: { text: string; error?: boolean }) { return <section className={`panel hub-message${error ? " error" : ""}`}>{text}</section>; }
