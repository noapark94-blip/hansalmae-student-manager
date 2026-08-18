"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { CorrectionWorkBoard } from "./correction-work-board";

export function AssignmentBoard({ supabase }: { supabase:SupabaseClient }) {
  return <div className="correction-management-workspace">
    <div className="page-heading correction-management-heading">
      <div><p className="eyebrow">한살매 첨삭 운영</p><h1>첨삭 관리</h1><p>첨삭 학생의 출결·과제 검사·시험·피드백을 한 화면에서 기록합니다.</p></div>
    </div>
    <CorrectionWorkBoard supabase={supabase} />
  </div>;
}
