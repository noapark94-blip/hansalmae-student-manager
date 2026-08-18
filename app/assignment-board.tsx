"use client";

import type { SupabaseClient } from "@supabase/supabase-js";
import { CorrectionManagementBoard } from "./correction-management-board";
import { CorrectionWorkBoard } from "./correction-work-board";

export function AssignmentBoard({ supabase }: { supabase:SupabaseClient }) {
  return <div className="correction-management-workspace">
    <CorrectionManagementBoard supabase={supabase} />
    <CorrectionWorkBoard supabase={supabase} />
  </div>;
}
