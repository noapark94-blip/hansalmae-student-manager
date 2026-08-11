"use client";

import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";

type HubTab = "all" | "teacher" | "correction" | "vehicle";
type Named = { id: string; name: string };
type ClassSchedule = { id: string; classId: string; className: string; subject: string; color: string; weekday: number; startTime: string; endTime: string; room: string | null; teachers: Named[] };
type Correction = { id: string; studentId: string; studentName: string; teacherId: string; teacherName: string; weekday: number; slotIndex: number };
type VehicleRun = { id: string; managerId: string; managerName: string; weekday: number; pickupTime: string; pickupLocation: string; students: Named[] };
type HubData = { teachers: Named[]; classSchedules: ClassSchedule[]; corrections: Correction[]; vehicles: VehicleRun[] };

const weekdays = ["월", "화", "수", "목", "금", "토"];
const correctionSlots = ["17:30–19:00", "19:00–20:30", "20:30–22:00"];

export function TeacherScheduleHub({ supabase, profile, initialTab }: { supabase: SupabaseClient; profile: Profile; initialTab: HubTab }) {
  const [tab, setTab] = useState<HubTab>(initialTab);
  const [teacherId, setTeacherId] = useState(profile.id);
  const [data, setData] = useState<HubData>({ teachers: [], classSchedules: [], corrections: [], vehicles: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => { setTab(initialTab); }, [initialTab]);
  useEffect(() => {
    let active = true;
    void supabase.rpc("staff_schedule_hub").then(({ data: result, error: loadError }) => {
      if (!active) return;
      if (loadError || !result) setError("시간표 데이터를 불러오지 못했습니다.");
      else setData(result as HubData);
      setLoading(false);
    });
    return () => { active = false; };
  }, [supabase]);

  const visibleClasses = useMemo(() => tab === "teacher" ? data.classSchedules.filter((item) => item.teachers.some((teacher) => teacher.id === teacherId)) : data.classSchedules, [data.classSchedules, tab, teacherId]);

  if (loading) return <ScheduleMessage text="시간표를 불러오는 중이에요…" />;
  if (error) return <ScheduleMessage text={error} error />;

  return <>
    <div className="page-heading compact"><div><p className="eyebrow">선생님 통합 일정</p><h1>시간표 허브</h1><p>전과목 일정과 개인 배정, 첨삭, 차량 운행을 한 화면에서 확인합니다.</p></div></div>
    <div className="schedule-tabs" role="tablist">
      <button className={tab === "all" ? "active" : ""} onClick={() => setTab("all")}>전과목 시간표</button>
      <button className={tab === "teacher" ? "active" : ""} onClick={() => setTab("teacher")}>선생님별 시간표</button>
      <button className={tab === "correction" ? "active" : ""} onClick={() => setTab("correction")}>첨삭 시간표</button>
      <button className={tab === "vehicle" ? "active" : ""} onClick={() => setTab("vehicle")}>차량 운행표</button>
    </div>
    {(tab === "all" || tab === "teacher") && <ClassScheduleBoard rows={visibleClasses} teachers={data.teachers} teacherId={teacherId} setTeacherId={setTeacherId} personal={tab === "teacher"} />}
    {tab === "correction" && <CorrectionBoard rows={data.corrections} />}
    {tab === "vehicle" && <VehicleBoard rows={data.vehicles} />}
  </>;
}

function ClassScheduleBoard({ rows, teachers, teacherId, setTeacherId, personal }: { rows: ClassSchedule[]; teachers: Named[]; teacherId: string; setTeacherId: (id: string) => void; personal: boolean }) {
  return <section className="panel hub-panel"><div className="hub-toolbar"><div><h2>{personal ? "선생님별 클래스 배정" : "학원 전과목 시간표"}</h2><span>전과목 시간표의 공동담당 배정이 개인 시간표에 자동 반영됩니다.</span></div>{personal && <select value={teacherId} onChange={(event) => setTeacherId(event.target.value)}>{teachers.map((teacher) => <option key={teacher.id} value={teacher.id}>{teacher.name}</option>)}</select>}</div><div className="week-column-grid">{weekdays.map((day, index) => <div className="week-column" key={day}><b>{day}</b>{rows.filter((row) => row.weekday === index + 1).map((row) => <article key={row.id} style={{ borderLeftColor:row.color }}><strong>{row.startTime.slice(0,5)}–{row.endTime.slice(0,5)}</strong><span>{row.className}</span><small>{row.subject}{row.room ? ` · ${row.room}` : ""}</small><em>{row.teachers.map((teacher) => teacher.name).join(" · ") || "담당 미배정"}</em></article>)}</div>)}</div>{rows.length === 0 && <Empty text="등록된 클래스 시간 배정이 없습니다." />}</section>;
}

function CorrectionBoard({ rows }: { rows: Correction[] }) {
  return <section className="panel hub-panel"><div className="hub-toolbar"><div><h2>고정 첨삭 시간표</h2><span>월–금 17:30부터 90분 단위이며, 담당쌤이 주간 예외를 변경합니다.</span></div></div><div className="correction-grid"><div className="correction-corner">시간</div>{weekdays.slice(0,5).map((day) => <b key={day}>{day}</b>)}{correctionSlots.flatMap((slot, slotIndex) => [<strong key={`${slot}-label`}>{slot}</strong>, ...weekdays.slice(0,5).map((day, dayIndex) => <div key={`${day}-${slot}`} className="correction-cell">{rows.filter((row) => row.weekday === dayIndex + 1 && row.slotIndex === slotIndex).map((row) => <span key={row.id}><b>{row.studentName}</b><small>{row.teacherName}쌤</small></span>)}</div>)])}</div>{rows.length === 0 && <Empty text="아직 배정된 고정 첨삭 시간이 없습니다." />}</section>;
}

function VehicleBoard({ rows }: { rows: VehicleRun[] }) {
  return <section className="panel hub-panel"><div className="hub-toolbar"><div><h2>차량 운행 시간표</h2><span>차량실장님별 탑승 시간·위치·탑승학생을 확인합니다.</span></div></div><div className="vehicle-week">{weekdays.map((day, index) => <div key={day}><b>{day}</b>{rows.filter((row) => row.weekday === index + 1).map((row) => <article key={row.id}><time>{row.pickupTime.slice(0,5)}</time><span><strong>{row.pickupLocation}</strong><small>차량실장님 · {row.managerName}</small><em>{row.students.map((student) => student.name).join(", ") || "탑승학생 미배정"}</em></span></article>)}</div>)}</div>{rows.length === 0 && <Empty text="아직 등록된 차량 운행 일정이 없습니다." />}</section>;
}

function Empty({ text }: { text: string }) { return <p className="hub-empty">{text}</p>; }
function ScheduleMessage({ text, error = false }: { text: string; error?: boolean }) { return <section className={`panel hub-message${error ? " error" : ""}`}>{text}</section>; }
