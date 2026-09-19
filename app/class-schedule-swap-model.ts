export type SwapSchedule = {
  id: string; classId: string; className: string; weekday: number;
  startTime: string; endTime: string; room: string | null;
  teachers: { id: string; name: string }[];
};
const minutes = (time: string) => Number(time.slice(0, 2)) * 60 + Number(time.slice(3, 5));
const clock = (value: number) => `${String(Math.floor(value / 60)).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}`;
export function scheduleSwapBase(row: SwapSchedule) {
  return { weekday: row.weekday, startTime: row.startTime.slice(0, 5), endTime: row.endTime.slice(0, 5), teacherIds: row.teachers.map(t => t.id).sort() };
}
export function previewScheduleSwap(first: SwapSchedule, second: SwapSchedule, all: SwapSchedule[]) {
  if (first.id === second.id || first.weekday !== second.weekday) return { rows: [], error: "같은 요일의 다른 수업을 선택해 주세요." };
  if (minutes(first.startTime) === minutes(second.startTime)) return { rows: [], error: "이미 시작 시간이 같은 수업입니다." };
  const rows = [first, second].map((row, i) => {
    const start = minutes(i === 0 ? second.startTime : first.startTime);
    const duration = minutes(row.endTime) - minutes(row.startTime);
    return { ...row, startTime: clock(start), endTime: clock(start + duration) };
  });
  if (rows.some(r => r.endTime >= "24:00" || r.endTime <= r.startTime)) return { rows: [], error: "맞바꾼 수업이 자정을 넘거나 시간이 올바르지 않습니다." };
  const final = [...all.filter(r => r.id !== first.id && r.id !== second.id), ...rows];
  const conflicts = rows.flatMap(row => final.filter(other => other.id !== row.id && other.weekday === row.weekday && other.startTime.slice(0,5) < row.endTime && other.endTime.slice(0,5) > row.startTime && (other.classId === row.classId || other.teachers.some(t => row.teachers.some(m => m.id === t.id)) || Boolean(row.room?.trim() && row.room.trim() === other.room?.trim()))).map(other => `${row.className} ↔ ${other.className}`));
  return { rows, error: conflicts.length ? `맞바꾼 시간에 겹치는 수업이 있어요: ${[...new Set(conflicts)].join(" / ")}` : "" };
}
