import type { SupabaseClient } from "@supabase/supabase-js";

// Query the chosen record's date, not its position within a recent-record list.
// Previous homework is loaded separately by record identity, without a date cap.
export async function loadFamilyDetailReports(supabase: SupabaseClient, studentId: string, date: string) {
  const parsed = new Date(`${date}T00:00:00Z`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0,10) !== date) throw new Error("유효하지 않은 수업 날짜입니다.");
  return loadFamilyPeriodReports(supabase,studentId,date,date);
}

export function loadFamilyCalendarReports(supabase: SupabaseClient, studentId: string, month: string) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new Error("유효하지 않은 조회 월입니다.");
  const [year,number] = month.split("-").map(Number);
  const end = new Date(Date.UTC(year,number,0)).toISOString().slice(0,10);
  return loadFamilyPeriodReports(supabase,studentId,`${month}-01`,end);
}

async function loadFamilyPeriodReports(supabase: SupabaseClient, studentId: string, start: string, end: string) {
  const result = await supabase.rpc("family_summary_snapshot", { p_student_id: studentId, p_start_date: start, p_end_date: end });
  const snapshot = result.data as { lessons?: unknown[]; corrections?: unknown[] } | null;
  const error = result.error ?? (!Array.isArray(snapshot?.lessons) || !Array.isArray(snapshot?.corrections) ? { message: "학습 기록을 불러오지 못했습니다." } : null);
  return [{ data: snapshot?.lessons ?? [], error }, { data: snapshot?.corrections ?? [], error }] as const;
}
