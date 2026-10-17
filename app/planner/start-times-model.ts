export const WEEKDAYS = ["월", "화", "수", "목", "금", "토", "일"];
export function generateStartTimes(start: string, interval: number): string[] {
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(start) || ![90, 120].includes(interval)) return [];
  const [hour, minute] = start.split(":").map(Number);
  const result: string[] = [];
  for (let t = hour * 60 + minute; t + interval <= 22 * 60; t += interval) {
    result.push(`${String(Math.floor(t / 60)).padStart(2, "0")}:${String(t % 60).padStart(2, "0")}`);
  }
  return result;
}
export function applyStartTimes(current: string[], selected: number[], times: string[]): string[] {
  return current.map((value, day) => selected.includes(day) ? times.join(",") : value);
}
