"use client";

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CorrectionManagementBoard } from "./correction-management-board";
import { CorrectionWorkBoard } from "./correction-work-board";
import "./correction-mode.css";

type CorrectionMode = "timetable" | "management";

function readMode():CorrectionMode{
  if(typeof window==="undefined")return "management";
  return window.sessionStorage.getItem("hansalmae:correction-mode")==="timetable"?"timetable":"management";
}

export function AssignmentBoard({ supabase }: { supabase:SupabaseClient }) {
  const[mode,setMode]=useState<CorrectionMode>(readMode);
  useEffect(()=>{
    const sync=()=>setMode(readMode());
    window.addEventListener("hansalmae-correction-mode",sync);
    return()=>window.removeEventListener("hansalmae-correction-mode",sync);
  },[]);
  if(mode==="timetable")return <div className="correction-timetable-mode"><div className="page-heading correction-timetable-title"><div><p className="eyebrow">한살매 첨삭 운영</p><h1>첨삭 시간표</h1><p>요일·시간 블록을 눌러 학생을 고정 배정하고, 이번 주만 변경·취소·추가할 수 있습니다.</p></div></div><div className="correction-management-workspace"><CorrectionManagementBoard supabase={supabase}/></div></div>;
  return <div className="correction-management-workspace">
    <div className="page-heading correction-management-heading">
      <div><p className="eyebrow">한살매 첨삭 운영</p><h1>첨삭 관리</h1><p>첨삭 학생의 출결·과제 검사·시험·피드백을 한 화면에서 기록합니다.</p></div>
    </div>
    <CorrectionWorkBoard supabase={supabase} />
  </div>;
}
