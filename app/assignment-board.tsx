"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { CorrectionWorkBoard } from "./correction-work-board";

export function AssignmentBoard({ supabase }: { supabase: SupabaseClient }) {
  return <div className="correction-management-workspace">
    <div className="page-heading correction-heading">
      <div>
        <p className="eyebrow">한살매 첨삭 운영</p>
        <h1>첨삭 관리</h1>
        <p>담당 선생님의 사전 지시를 확인하고 과제·시험·첨삭 결과를 한 화면에서 기록합니다.</p>
      </div>
    </div>
    <CorrectionWorkBoard supabase={supabase} />
  </div>;
}
