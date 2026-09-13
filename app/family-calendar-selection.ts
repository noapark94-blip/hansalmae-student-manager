// Preserve the selected day when moving months, clamped to the month's last day.
export function calendarMonthSelection(month: string, selectedDate: string) {
  const [year, number] = month.split("-").map(Number);
  const lastDay = new Date(Date.UTC(year, number, 0)).getUTCDate();
  const day = Math.min(Number(selectedDate.slice(8,10)), lastDay);
  return `${month}-${String(day).padStart(2,"0")}`;
}
