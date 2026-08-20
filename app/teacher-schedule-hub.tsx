"use client";

import type { CSSProperties, FormEvent, ReactNode } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { isMilitaryTime, MilitaryTimeInput } from "./military-time-input";

type HubTab = "all" | "teacher" | "correction" | "vehicle";
type Named = { id: string; name: string };
type ClassSchedule = { id: string; classId: string; className: string; subject: string; color: string; weekday: number; startTime: string; endTime: string; room: string | null; teachers: Named[]; students:Named[] };
type Correction = { id: string; studentId: string; studentName: string; teacherId: string; teacherName: string; weekday: number; slotIndex: number };
type CorrectionException = { id: string; assignmentId: string; weekStart: string; weekday: number; slotIndex: number; note: string | null };
type VehicleRun = { id: string; managerId: string; managerName: string; weekday: number; pickupTime: string; pickupLocation: string; routeName:string;direction:"pickup"|"dropoff";stopOrder:number;students: Named[];changed?:boolean };
type VehicleException={id:string;runId:string;serviceDate:string;kind:"changed"|"cancelled";pickupTime:string|null;pickupLocation:string|null;note:string|null};
type VehicleGuardian={name:string;phone:string;relationship:string|null;isPrimary:boolean};
type VehicleActivity={type:"class"|"correction";title:string;subject:string|null;startTime:string;endTime:string};
type AutoVehicleRow={studentId:string;studentName:string;school:string|null;grade:string|null;studentPhone:string|null;residence:string|null;pickupLocation:string|null;dropoffLocation:string|null;guardians:VehicleGuardian[];activities:VehicleActivity[];weekday:number;pickupTime:string|null;dropoffTime:string|null;sources:string[];pickupExcluded:boolean;dropoffExcluded:boolean};
type HubData = { teachers: Named[]; students: Named[]; classes: Named[]; classSchedules: ClassSchedule[]; corrections: Correction[]; correctionExceptions: CorrectionException[]; vehicles: VehicleRun[];vehicleExceptions:VehicleException[];todayVehicles:VehicleRun[];autoVehicles:AutoVehicleRow[] };
type Editor = { kind: "class"; row?: ClassSchedule } | { kind: "correction"; row?: Correction } | { kind: "exception"; row: Correction } | { kind: "vehicle"; row?: VehicleRun }|{kind:"vehicleException";row:VehicleRun} | null;

const emptyData: HubData = { teachers: [], students: [], classes: [], classSchedules: [], corrections: [], correctionExceptions: [], vehicles: [],vehicleExceptions:[],todayVehicles:[],autoVehicles:[] };
const weekdays = ["월", "화", "수", "목", "금", "토", "일"];
const correctionSlots = ["17:30–19:00", "19:00–20:30", "20:30–22:00"];

export function TeacherScheduleHub({ supabase, profile, initialTab }: { supabase: SupabaseClient; profile: Profile; initialTab: HubTab }) {
  const [tab, setTab] = useState<HubTab>(initialTab);
  const [teacherId, setTeacherId] = useState(profile.id);
  const [data, setData] = useState<HubData>(emptyData);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [editor, setEditor] = useState<Editor>(null);
  const [roster, setRoster] = useState<ClassSchedule|null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError("");
    const [{data:result,error:loadError},{data:vehicleResult,error:vehicleError},{data:rosterResult,error:rosterError},{data:autoVehicleResult,error:autoVehicleError}]=await Promise.all([supabase.rpc("staff_schedule_hub"),supabase.rpc("staff_vehicle_operations"),supabase.rpc("staff_class_schedule_rosters"),supabase.rpc("staff_auto_vehicle_schedule")]);
    if (loadError || !result||vehicleError||!vehicleResult||rosterError||autoVehicleError) setError("시간표 데이터를 불러오지 못했습니다.");
    else { const hub={ ...emptyData, ...(result as Partial<HubData>),...(vehicleResult as Partial<HubData>),autoVehicles:(autoVehicleResult??[]) as AutoVehicleRow[] }; const rosterMap=new Map(((rosterResult??[]) as {classId:string;students:Named[]}[]).map((item)=>[item.classId,item.students])); setData({...hub,classSchedules:hub.classSchedules.map((item)=>({...item,students:rosterMap.get(item.classId)??[]}))}); }
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
    {(tab === "all" || tab === "teacher") && <ClassScheduleBoard rows={visibleClasses} teachers={data.teachers} teacherId={teacherId} setTeacherId={setTeacherId} personal={tab === "teacher"} onAdd={() => setEditor({ kind: "class" })} onEdit={(row) => setEditor({ kind: "class", row })} onRoster={setRoster} />}
    {tab === "correction" && <CorrectionBoard rows={data.corrections} exceptions={data.correctionExceptions} profile={profile} onAdd={() => setEditor({ kind: "correction" })} onEdit={(row) => setEditor({ kind: "correction", row })} onException={(row) => setEditor({ kind: "exception", row })} />}
    {tab === "vehicle" && <VehicleBoard rows={data.autoVehicles} supabase={supabase} onChanged={loadData} />}
    {editor?.kind === "class" && <ClassEditor supabase={supabase} data={data} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind === "correction" && <CorrectionEditor supabase={supabase} data={data} profile={profile} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind === "exception" && <ExceptionEditor supabase={supabase} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind === "vehicle" && <VehicleEditor supabase={supabase} data={data} row={editor.row} onClose={() => setEditor(null)} onSaved={saved} />}
    {editor?.kind==="vehicleException"&&<VehicleExceptionEditor supabase={supabase} row={editor.row} onClose={()=>setEditor(null)} onSaved={saved}/>}
    {roster&&<ClassRosterModal row={roster} onClose={()=>setRoster(null)} onEdit={()=>{setRoster(null);setEditor({kind:"class",row:roster});}}/>}
  </>;
}

function ClassScheduleBoard({ rows, teachers, teacherId, setTeacherId, personal, onAdd, onEdit,onRoster }: { rows: ClassSchedule[]; teachers: Named[]; teacherId: string; setTeacherId: (id: string) => void; personal: boolean; onAdd: () => void; onEdit: (row: ClassSchedule) => void;onRoster:(row:ClassSchedule)=>void }) {
  const groups=Array.from(new Map(rows.map((row)=>[`${row.startTime.slice(0,5)}-${row.endTime.slice(0,5)}`,{start:row.startTime.slice(0,5),end:row.endTime.slice(0,5)}])).values()).sort((a,b)=>a.start.localeCompare(b.start)||a.end.localeCompare(b.end));
  return <section className="panel hub-panel"><HubToolbar title={personal ? "선생님별 클래스 배정" : "학원 전과목 시간표"} description="요일이 달라도 같은 시간대는 한 줄에, 요일과 시간이 모두 같으면 같은 칸에 함께 표시됩니다."><>{personal && <select value={teacherId} onChange={(event) => setTeacherId(event.target.value)}>{teachers.map((teacher) => <option key={teacher.id} value={teacher.id}>{teacher.name}</option>)}</select>}<button className="primary hub-add" onClick={onAdd}>＋ 수업 배정</button></></HubToolbar>{rows.length>0&&<div className="aligned-schedule"><div className="aligned-schedule-head"><b>시간</b>{weekdays.map((day)=><b key={day}>{day}</b>)}</div>{groups.map((group)=><div className="aligned-schedule-row" key={`${group.start}-${group.end}`}><strong><time>{group.start}–{group.end}</time></strong>{weekdays.map((day,dayIndex)=><div key={day}>{rows.filter((row)=>row.weekday===dayIndex+1&&row.startTime.slice(0,5)===group.start&&row.endTime.slice(0,5)===group.end).map((row)=><article className="aligned-class-card" key={row.id} style={{"--schedule-color":row.color} as CSSProperties}><button className="aligned-class-main" onClick={()=>onRoster(row)}><b>{row.className}</b><small>{row.subject} · {row.teachers.map((teacher)=>teacher.name).join("·")||"담당 미배정"}{row.room?` · ${row.room}`:""}</small><em>{row.students.length}명 · 명단 보기</em></button><button className="aligned-class-edit" aria-label={`${row.className} 수업 배정 수정`} onClick={()=>onEdit(row)}>수정</button></article>)}</div>)}</div>)}</div>}{rows.length === 0 && <Empty text="등록된 클래스 시간 배정이 없습니다." />}</section>;
}

function ClassRosterModal({row,onClose,onEdit}:{row:ClassSchedule;onClose:()=>void;onEdit:()=>void}){return <EditorModal title={row.className} description={`${weekdays[row.weekday-1]}요일 ${row.startTime.slice(0,5)}–${row.endTime.slice(0,5)} · ${row.subject}`} onClose={onClose}><div className="class-roster-modal"><header><b>수강 학생 명단</b><span>총 {row.students.length}명</span></header>{row.students.length?<div>{row.students.map((student,index)=><p key={student.id}><i>{index+1}</i><b>{student.name}</b></p>)}</div>:<Empty text="현재 수강 중인 학생이 없습니다."/>}<footer><button className="secondary-button" onClick={onClose}>닫기</button><button className="primary" onClick={onEdit}>수업 배정 수정</button></footer></div></EditorModal>}

function CorrectionBoard({ rows, exceptions, profile, onAdd, onEdit, onException }: { rows: Correction[]; exceptions: CorrectionException[]; profile: Profile; onAdd: () => void; onEdit: (row: Correction) => void; onException: (row: Correction) => void }) {
  const upcoming = exceptions.filter((item) => item.weekStart >= getMonday()).slice(0, 6);
  return <section className="panel hub-panel"><HubToolbar title="고정 첨삭 시간표" description="현재 운영 중인 고정 첨삭 배정을 확인합니다. 정원 제한 없이 학생을 배정할 수 있습니다."><button className="primary hub-add" onClick={onAdd}>＋ 내 학생 배정</button></HubToolbar>{upcoming.length > 0 && <div className="exception-strip"><b>예정된 주간 변경</b>{upcoming.map((item) => { const assignment = rows.find((row) => row.id === item.assignmentId); return <span key={item.id}>{item.weekStart} · {assignment?.studentName ?? "학생"} → {weekdays[item.weekday - 1]} {correctionSlots[item.slotIndex]}</span>; })}</div>}<div className="correction-grid"><div className="correction-corner">시간</div>{weekdays.slice(0,5).map((day) => <b key={day}>{day}</b>)}{correctionSlots.flatMap((slot, slotIndex) => [<strong key={`${slot}-label`}>{slot}</strong>, ...weekdays.slice(0,5).map((day, dayIndex) => <div key={`${day}-${slot}`} className="correction-cell">{rows.filter((row) => row.weekday === dayIndex + 1 && row.slotIndex === slotIndex).map((row) => <span key={row.id} className={row.teacherId === profile.id ? "editable" : ""}><b>{row.studentName}</b><small>{row.teacherName}쌤</small>{row.teacherId === profile.id && <i><button onClick={() => onEdit(row)}>고정 변경</button><button onClick={() => onException(row)}>이번 주만</button></i>}</span>)}</div>)])}</div>{rows.length === 0 && <Empty text="아직 배정된 고정 첨삭 시간이 없습니다." />}</section>;
}

function VehicleBoard({rows,supabase,onChanged}:{rows:AutoVehicleRow[];supabase:SupabaseClient;onChanged:()=>Promise<void>}){
  const today=new Date().getDay();
  const[selectedDay,setSelectedDay]=useState(today>=1&&today<=5?today:1);
  const[showExcluded,setShowExcluded]=useState(false);
  const[selectedStudent,setSelectedStudent]=useState<AutoVehicleRow|null>(null);
  const[saving,setSaving]=useState("");
  const[error,setError]=useState("");
  const times=["16:00","17:30","19:00","20:30"];
  const dayRows=rows.filter(row=>row.weekday===selectedDay);
  const excludedCount=dayRows.reduce((sum,row)=>sum+(row.pickupExcluded&&row.pickupTime?1:0)+(row.dropoffExcluded&&row.dropoffTime?1:0),0);
  const setExcluded=async(row:AutoVehicleRow,direction:"pickup"|"dropoff",excluded:boolean)=>{
    const key=`${row.studentId}-${direction}`;setSaving(key);setError("");
    const{error:saveError}=await supabase.rpc("staff_set_vehicle_schedule_exclusion",{p_student_id:row.studentId,p_weekday:selectedDay,p_direction:direction,p_excluded:excluded});
    if(saveError){setError("차량 이용 여부를 저장하지 못했습니다.");setSaving("");return}
    await onChanged();setSaving("");
  };
  const students=(time:string,direction:"pickup"|"dropoff")=>dayRows.filter(row=>(direction==="pickup"?row.pickupTime:row.dropoffTime)?.slice(0,5)===time&&!(direction==="pickup"?row.pickupExcluded:row.dropoffExcluded));
  const excluded=dayRows.flatMap(row=>[
    ...(row.pickupTime&&row.pickupExcluded?[{row,direction:"pickup" as const,time:row.pickupTime.slice(0,5)}]:[]),
    ...(row.dropoffTime&&row.dropoffExcluded?[{row,direction:"dropoff" as const,time:row.dropoffTime.slice(0,5)}]:[])
  ]);
  const renderStudent=(row:AutoVehicleRow,direction:"pickup"|"dropoff")=>{
    const key=`${row.studentId}-${direction}`;
    return <article className="auto-vehicle-student" key={key}><div><button type="button" className="auto-vehicle-student-name" onClick={()=>setSelectedStudent(row)}>{row.studentName}</button><small>{[row.school,row.grade,row.sources.join("·")].filter(Boolean).join(" · ")}</small></div><button type="button" disabled={saving===key} onClick={()=>void setExcluded(row,direction,true)}>차량 제외</button></article>;
  };
  return <section className="panel hub-panel auto-vehicle-board">
    <HubToolbar title="차량 운행표" description="정규수업과 첨삭 일정을 합쳐 첫 시작 시간은 등원, 마지막 종료 시간은 하원으로 자동 표시합니다."><button type="button" className={showExcluded?"secondary-button active":"secondary-button"} onClick={()=>setShowExcluded(value=>!value)}>제외 학생 {excludedCount}명</button></HubToolbar>
    <nav className="auto-vehicle-days" aria-label="차량 운행 요일">{weekdays.slice(0,5).map((day,index)=><button type="button" key={day} className={selectedDay===index+1?"active":""} onClick={()=>setSelectedDay(index+1)}>{day}요일</button>)}</nav>
    {error?<p className="form-error">{error}</p>:null}
    <div className="auto-vehicle-legend"><span className="pickup">등원</span><span className="dropoff">하원</span><small>연속 수업·첨삭은 첫 등원과 마지막 하원에만 표시됩니다.</small></div>
    <div className="auto-vehicle-grid">
      <div className="auto-vehicle-grid-head"><b>시간</b><b className="pickup">등원 학생</b><b className="dropoff">하원 학생</b></div>
      {times.map(time=>{const pickup=students(time,"pickup"),dropoff=students(time,"dropoff");return <div className="auto-vehicle-grid-row" key={time}><strong>{time}</strong><section className="pickup">{pickup.length?pickup.map(row=>renderStudent(row,"pickup")):<p>등원 학생 없음</p>}</section><section className="dropoff">{dropoff.length?dropoff.map(row=>renderStudent(row,"dropoff")):<p>하원 학생 없음</p>}</section></div>})}
    </div>
    {showExcluded?<section className="auto-vehicle-excluded"><header><b>{weekdays[selectedDay-1]}요일 차량 제외 학생</b><span>수업·첨삭 일정은 유지됩니다.</span></header>{excluded.length?<div>{excluded.map(({row,direction,time})=>{const key=`${row.studentId}-${direction}`;return <article key={key}><span className={direction}>{direction==="pickup"?"등원":"하원"} · {time}</span><b>{row.studentName}</b><button type="button" disabled={saving===key} onClick={()=>void setExcluded(row,direction,false)}>다시 포함</button></article>})}</div>:<p>제외된 학생이 없습니다.</p>}</section>:null}
    {selectedStudent?<VehicleStudentDetailModal row={selectedStudent} onClose={()=>setSelectedStudent(null)}/>:null}
  </section>;
}

function VehicleStudentDetailModal({row,onClose}:{row:AutoVehicleRow;onClose:()=>void}){
  const guardians=row.guardians??[];
  const activities=row.activities??[];
  const value=(text:string|null|undefined)=>text?.trim()||"미입력";
  return <div className="modal-backdrop nested" onMouseDown={(event)=>{if(event.target===event.currentTarget)onClose();}}><section className="student-modal vehicle-student-detail-modal" role="dialog" aria-modal="true" aria-labelledby="vehicle-student-detail-title"><header><div><p className="eyebrow">차량 학생 정보</p><h2 id="vehicle-student-detail-title">{row.studentName}</h2><span>{[row.school,row.grade].filter(Boolean).join(" · ")||"학교·학년 미입력"}</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><div className="vehicle-student-detail-body"><dl><div><dt>거주지</dt><dd>{value(row.residence)}</dd></div><div><dt>승차 위치</dt><dd>{value(row.pickupLocation)}</dd></div><div><dt>하차 위치</dt><dd>{value(row.dropoffLocation)}</dd></div><div><dt>학생 연락처</dt><dd>{value(row.studentPhone)}</dd></div><div className="full"><dt>보호자 연락처</dt><dd>{guardians.length?guardians.map((guardian)=><span key={`${guardian.name}-${guardian.phone}`}><b>{guardian.name}{guardian.isPrimary?" · 주 보호자":""}</b>{guardian.phone||"연락처 미입력"}{guardian.relationship?` · ${guardian.relationship}`:""}</span>):"미입력"}</dd></div></dl><section className="vehicle-student-schedule"><header><b>{weekdays[row.weekday-1]}요일 정규수업·첨삭</b></header>{activities.length?<div>{activities.map((activity,index)=><article key={`${activity.type}-${activity.startTime}-${index}`}><span className={activity.type}>{activity.type==="class"?"정규수업":"첨삭"}</span><div><b>{activity.title}</b><small>{activity.startTime.slice(0,5)}–{activity.endTime.slice(0,5)}{activity.subject?` · ${activity.subject}`:""}</small></div></article>)}</div>:<p>등록된 일정이 없습니다.</p>}</section></div></section></div>;
}
function ClassEditor({ supabase, data, row, onClose, onSaved }: EditorProps & { data: HubData; row?: ClassSchedule }) {
  const [classId, setClassId] = useState(row?.classId ?? data.classes[0]?.id ?? "");
  const [weekday, setWeekday] = useState(row?.weekday ?? 1);
  const [startTime, setStartTime] = useState(row?.startTime.slice(0,5) ?? "17:30");
  const [endTime, setEndTime] = useState(row?.endTime.slice(0,5) ?? "19:00");
  const [teacherIds, setTeacherIds] = useState(row?.teachers.map((item) => item.id) ?? []);
  const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  useEffect(() => { if (!row) setTeacherIds(data.classSchedules.find((item) => item.classId === classId)?.teachers.map((item) => item.id) ?? []); }, [classId, data.classSchedules, row]);
  const selectedRoom=row?.classId===classId?row.room:data.classSchedules.find((item)=>item.classId===classId)?.room??null;
  const conflicts=useMemo(()=>data.classSchedules.filter((item)=>item.id!==row?.id&&item.weekday===weekday&&item.startTime.slice(0,5)<endTime&&item.endTime.slice(0,5)>startTime&&(item.classId===classId||item.teachers.some((teacher)=>teacherIds.includes(teacher.id))||Boolean(selectedRoom&&item.room===selectedRoom))),[classId,data.classSchedules,endTime,row?.id,selectedRoom,startTime,teacherIds,weekday]);
  const submit = async (event: FormEvent) => { event.preventDefault(); if (!classId || teacherIds.length === 0) return setError("클래스와 담당 선생님을 한 명 이상 선택해 주세요."); if (!isMilitaryTime(startTime)||!isMilitaryTime(endTime)||startTime >= endTime) return setError("시간을 24시간제 네 자리로 입력해 주세요. 예: 1730"); if(conflicts.length)return setError("겹치는 수업을 먼저 확인해 주세요."); setSaving(true); const { error: saveError } = await supabase.rpc("staff_save_class_schedule", { p_schedule_id: row?.id ?? null, p_class_id: classId, p_weekday: weekday, p_start_time: startTime, p_end_time: endTime, p_teacher_ids: teacherIds }); if (saveError) { setError(saveErrorMessage(saveError.message, "수업 배정을 저장하지 못했습니다.")); setSaving(false); return; } await onSaved(); };
  const remove = async () => { if (!row || !confirm("이 수업 시간 배정을 삭제할까요?")) return; setSaving(true); const { error: deleteError } = await supabase.from("class_schedules").delete().eq("id", row.id); if (deleteError) { setError("수업 배정을 삭제하지 못했습니다."); setSaving(false); } else await onSaved(); };
  return <EditorModal title={row ? "수업 배정 수정" : "수업 배정 등록"} description="공동담당 선생님은 모두 개인 시간표에 자동 표시됩니다." onClose={onClose}><form onSubmit={submit}><FormSelect label="클래스" value={classId} onChange={setClassId} options={data.classes} disabled={Boolean(row)} /><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={7} /><MilitaryTimeInput label="시작 시간" value={startTime} onChange={setStartTime}/><MilitaryTimeInput label="종료 시간" value={endTime} onChange={setEndTime}/></div><CheckList label="공동담당 선생님" rows={data.teachers} selected={teacherIds} onChange={setTeacherIds} />{conflicts.length>0&&<div className="schedule-conflict-preview"><b>겹치는 수업 {conflicts.length}건</b>{conflicts.map((item)=><span key={item.id}><strong>{weekdays[item.weekday-1]} {item.startTime.slice(0,5)}–{item.endTime.slice(0,5)} · {item.className}</strong><small>{item.room?`${item.room} · `:""}{item.teachers.map((teacher)=>teacher.name).join(" · ")}</small></span>)}</div>}{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} editing={Boolean(row)} onDelete={remove} /></form></EditorModal>;
}

function CorrectionEditor({ supabase, data, profile, row, onClose, onSaved }: EditorProps & { data: HubData; profile: Profile; row?: Correction }) {
  const [studentId, setStudentId] = useState(row?.studentId ?? data.students[0]?.id ?? ""); const [weekday, setWeekday] = useState(row?.weekday ?? 1); const [slotIndex, setSlotIndex] = useState(row?.slotIndex ?? 0); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const submit = async (event: FormEvent) => { event.preventDefault(); setSaving(true); const payload = { student_id: studentId, teacher_profile_id: profile.id, weekday, slot_index: slotIndex }; const result = row ? await supabase.from("correction_assignments").update(payload).eq("id", row.id) : await supabase.from("correction_assignments").insert(payload); if (result.error) { setError(saveErrorMessage(result.error.message, "첨삭 배정을 저장하지 못했습니다. 본인 담당 배정인지 확인해 주세요.")); setSaving(false); } else await onSaved(); };
  const remove = async () => { if (!row || !confirm("이 학생의 고정 첨삭 배정을 삭제할까요?")) return; setSaving(true); const { error: deleteError } = await supabase.from("correction_assignments").delete().eq("id", row.id); if (deleteError) { setError("첨삭 배정을 삭제하지 못했습니다."); setSaving(false); } else await onSaved(); };
  return <EditorModal title={row ? "고정 첨삭 변경" : "내 학생 첨삭 배정"} description={`${profile.display_name} 선생님 담당으로 저장됩니다.`} onClose={onClose}><form onSubmit={submit}><FormSelect label="학생" value={studentId} onChange={setStudentId} options={data.students} /><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={5} /><SlotSelect value={slotIndex} onChange={setSlotIndex} /></div>{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} editing={Boolean(row)} onDelete={remove} /></form></EditorModal>;
}

function ExceptionEditor({ supabase, row, onClose, onSaved }: EditorProps & { row: Correction }) {
  const [weekStart, setWeekStart] = useState(getMonday()); const [weekday, setWeekday] = useState(row.weekday); const [slotIndex, setSlotIndex] = useState(row.slotIndex); const [note, setNote] = useState(""); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const submit = async (event: FormEvent) => { event.preventDefault(); setSaving(true); const { error: saveError } = await supabase.from("correction_exceptions").upsert({ assignment_id: row.id, week_start: weekStart, weekday, slot_index: slotIndex, note: note.trim() || null }, { onConflict: "assignment_id,week_start" }); if (saveError) { setError(saveErrorMessage(saveError.message, "이번 주 변경을 저장하지 못했습니다. 담당 선생님만 변경할 수 있습니다.")); setSaving(false); } else await onSaved(); };
  return <EditorModal title="이번 주만 시간 변경" description={`${row.studentName} 학생의 고정 시간은 유지되고 선택한 주에만 적용됩니다.`} onClose={onClose}><form onSubmit={submit}><FormField label="변경할 주의 월요일"><input type="date" value={weekStart} onChange={(e) => setWeekStart(e.target.value)} required /></FormField><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={5} /><SlotSelect value={slotIndex} onChange={setSlotIndex} /></div><FormField label="변경 메모"><input value={note} onChange={(e) => setNote(e.target.value)} placeholder="예: 학교 행사로 목요일 변경" /></FormField>{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} /></form></EditorModal>;
}

function VehicleExceptionEditor({supabase,row,onClose,onSaved}:EditorProps&{row:VehicleRun}){
  const[serviceDate,setServiceDate]=useState(getToday());const[kind,setKind]=useState<"changed"|"cancelled">("changed");const[pickupTime,setPickupTime]=useState(row.pickupTime.slice(0,5));const[location,setLocation]=useState(row.pickupLocation);const[note,setNote]=useState("");const[saving,setSaving]=useState(false);const[error,setError]=useState("");
  const submit=async(event:FormEvent)=>{event.preventDefault();const selectedWeekday=new Date(`${serviceDate}T00:00:00`).getDay()||7;if(selectedWeekday!==row.weekday)return setError(`${weekdays[row.weekday-1]}요일 날짜를 선택해 주세요.`);setSaving(true);setError("");const{error:saveError}=await supabase.from("vehicle_run_exceptions").upsert({run_id:row.id,service_date:serviceDate,kind,pickup_time:kind==="changed"?pickupTime:null,pickup_location:kind==="changed"?location.trim():null,note:note.trim()||null},{onConflict:"run_id,service_date"});if(saveError){setError(saveErrorMessage(saveError.message,"날짜별 운행 변경을 저장하지 못했습니다."));setSaving(false);}else await onSaved();};
  return <EditorModal title="날짜별 차량 운행 변경" description={`${row.routeName} ${weekdays[row.weekday-1]}요일 ${row.pickupLocation} 고정 운행은 유지됩니다.`} onClose={onClose}><form onSubmit={submit}><div className="form-pair"><FormField label="적용 날짜"><input type="date" min={getToday()} value={serviceDate} onChange={(event)=>setServiceDate(event.target.value)} required/></FormField><FormField label="처리"><select value={kind} onChange={(event)=>setKind(event.target.value as "changed"|"cancelled")}><option value="changed">이 날짜만 변경</option><option value="cancelled">이 날짜만 운행 취소</option></select></FormField></div>{kind==="changed"&&<><div className="form-pair"><FormField label="변경 시간"><input type="time" value={pickupTime} onChange={(event)=>setPickupTime(event.target.value)} required/></FormField><FormField label="변경 위치"><input value={location} onChange={(event)=>setLocation(event.target.value)} required/></FormField></div></>}<FormField label="변경 메모"><input value={note} onChange={(event)=>setNote(event.target.value)} placeholder="예: 학교 행사로 정문 대신 후문"/></FormField>{error&&<p className="form-error">{error}</p>}<EditorFooter saving={saving}/></form></EditorModal>;
}

function VehicleEditor({ supabase, data, row, onClose, onSaved }: EditorProps & { data: HubData; row?: VehicleRun }) {
  const [managerId, setManagerId] = useState(row?.managerId ?? data.teachers[0]?.id ?? ""); const [weekday, setWeekday] = useState(row?.weekday ?? 1); const [pickupTime, setPickupTime] = useState(row?.pickupTime.slice(0,5) ?? "17:00"); const [location, setLocation] = useState(row?.pickupLocation ?? ""); const[routeName,setRouteName]=useState(row?.routeName??"1호차");const[direction,setDirection]=useState<"pickup"|"dropoff">(row?.direction??"pickup");const[stopOrder,setStopOrder]=useState(row?.stopOrder??1); const [studentIds, setStudentIds] = useState(row?.students.map((item) => item.id) ?? []); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const submit = async (event: FormEvent) => { event.preventDefault(); if (!managerId || !location.trim()||!routeName.trim()) return setError("노선명, 차량실장님과 위치를 입력해 주세요."); setSaving(true); const { error: saveError } = await supabase.rpc("staff_save_vehicle_run", { p_run_id: row?.id ?? null, p_manager_id: managerId, p_weekday: weekday, p_pickup_time: pickupTime, p_pickup_location: location.trim(), p_student_ids: studentIds,p_route_name:routeName.trim(),p_direction:direction,p_stop_order:stopOrder }); if (saveError) return fail(saveErrorMessage(saveError.message, "운행 정보를 저장하지 못했습니다.")); await onSaved(); };
  const fail = (message: string) => { setError(message); setSaving(false); };
  const remove = async () => { if (!row || !confirm("이 차량 운행 일정을 삭제할까요?")) return; setSaving(true); const { error: deleteError } = await supabase.from("vehicle_runs").delete().eq("id", row.id); if (deleteError) fail("운행 일정을 삭제하지 못했습니다."); else await onSaved(); };
  return <EditorModal title={row ? "차량 정류장 수정" : "차량 정류장 등록"} description="같은 노선의 정류장을 순서대로 등록하면 오늘 운행표에 자동 정렬됩니다." onClose={onClose}><form onSubmit={submit}><div className="form-pair"><FormField label="노선명"><input value={routeName} onChange={(event)=>setRouteName(event.target.value)} placeholder="예: 1호차" required/></FormField><FormSelect label="차량실장님" value={managerId} onChange={setManagerId} options={data.teachers} /><FormField label="승하차"><select value={direction} onChange={(event)=>setDirection(event.target.value as "pickup"|"dropoff")}><option value="pickup">승차</option><option value="dropoff">하차</option></select></FormField></div><div className="form-pair"><DaySelect value={weekday} onChange={setWeekday} count={6} /><FormField label="시간"><input type="time" value={pickupTime} onChange={(e) => setPickupTime(e.target.value)} required /></FormField><FormField label="정류장 순서"><input type="number" min={1} max={99} value={stopOrder} onChange={(event)=>setStopOrder(Number(event.target.value))} required/></FormField></div><FormField label="위치"><input value={location} onChange={(e) => setLocation(e.target.value)} placeholder="예: 배곧중학교 정문" required /></FormField><CheckList label="탑승학생" rows={data.students} selected={studentIds} onChange={setStudentIds} />{error && <p className="form-error">{error}</p>}<EditorFooter saving={saving} editing={Boolean(row)} onDelete={remove} /></form></EditorModal>;
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
function getToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function saveErrorMessage(message: string, fallback: string) { return message.includes("요일") || message.includes("오늘 이후") || message.includes("겹치는") || message.includes("시간 충돌") || message.includes("같은 시간") || message.includes("같은 시각") || message.includes("같은 첨삭") || message.includes("이미 배정") || message.includes("이미 있") || message.includes("늦어야") ? message : fallback; }
function Empty({ text }: { text: string }) { return <p className="hub-empty">{text}</p>; }
function ScheduleMessage({ text, error = false }: { text: string; error?: boolean }) { return <section className={`panel hub-message${error ? " error" : ""}`}>{text}</section>; }
