import { clock, domains, type Config, type Meeting } from "./engine";
import type { PrintableSchedule } from "../timetable-print-model";

export function boardDayGroups(config: Config, meetings: Meeting[]) {
  const slots = config.courses.filter(c => c.enabled).flatMap(c => domains(c, config));
  return [
    { label: "평일", days: [1, 2, 3, 4, 5] },
    { label: "주말", days: [6, 7] },
  ].map(group => ({ ...group, starts: [...new Set([...slots, ...meetings].filter(s => group.days.includes(s.day)).map(s => s.start))].sort((a, b) => a - b) }));
}

export function plannerPrintRows(config: Config, meetings: Meeting[], teacherFilter = ""): PrintableSchedule[] {
  const courses = new Map(config.courses.filter(c => c.enabled).map(c => [c.id, c]));
  return meetings.flatMap((m, index) => {
    const c = courses.get(m.classId);
    if (!c || (teacherFilter && !c.teachers.includes(teacherFilter))) return [];
    return [{ id: `${c.id}:${m.day}:${m.start}:${index}`, classId: c.id, weekday: m.day,
      startTime: clock(m.start), endTime: clock(m.end), className: c.name, subject: c.subject,
      color: "#a26f8c", room: c.room, students: c.students,
      teachers: config.teachers.filter(t => c.teachers.includes(t.id)).map(t => ({ id: t.id, name: t.name })) }];
  });
}
