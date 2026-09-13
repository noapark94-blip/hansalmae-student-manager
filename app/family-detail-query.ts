import type { SupabaseClient } from "@supabase/supabase-js";

// Query the chosen record's date, not its position within a recent-record list.
// Include preceding days so the detail can still show previous homework.
export async function loadFamilyDetailReports(supabase: SupabaseClient, studentId: string, date: string) {
  const parsed = new Date(`${date}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0,10) !== date) throw new Error("유효하지 않은 수업 날짜입니다.");
  const start = new Date(parsed.getTime() - 31 * 86400000).toISOString().slice(0,10);
  const result = await supabase.rpc("family_summary_snapshot", { p_student_id: studentId, p_start_date: start, p_end_date: date });
  const snapshot = result.data as { lessons?: unknown[]; corrections?: unknown[] } | null;
  const error = result.error ?? (!Array.isArray(snapshot?.lessons) || !Array.isArray(snapshot?.corrections) ? { message: "학습 기록을 불러오지 못했습니다." } : null);
  return [{ data: snapshot?.lessons ?? [], error }, { data: snapshot?.corrections ?? [], error }] as const;
}
