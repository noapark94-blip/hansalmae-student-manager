import type { StudentRow } from "./supabase";

export type RosterField = "school" | "grade" | "classes" | "status" | "phone" | "guardianPhones" | "check" | "memo";
export type RosterSort = "current" | "name" | "class" | "school" | "grade";
export type RosterPrintOptions = {
  title: string;
  sort: RosterSort;
  orientation: "portrait" | "landscape";
  fields: RosterField[];
};
export type RosterScope = { summary: string; classId?: string; subject?: string };
export type RosterGroup = { id: string; title: string; students: StudentRow[] };
export const ROSTER_FIELDS: { id: RosterField; label: string }[] = [
  { id: "school", label: "학교" }, { id: "grade", label: "학년" },
  { id: "classes", label: "수강반" }, { id: "status", label: "재원 상태" },
  { id: "phone", label: "학생 연락처" }, { id: "guardianPhones", label: "보호자 연락처" },
  { id: "check", label: "확인란" }, { id: "memo", label: "메모칸" },
];
export const defaultRosterOptions = (): RosterPrintOptions => ({
  title: "학생명단", sort: "name", orientation: "portrait", fields: ["school", "grade", "classes", "check"],
});
const collator = new Intl.Collator("ko", { numeric: true });
function activeClasses(student: StudentRow) {
  return Array.from(new Map(student.enrollments.filter(e => e.status === "active" && e.classes).map(e => [e.class_id, e])).values());
}
function gradeRank(grade: string | null) {
  const match = grade?.match(/^(초|중|고)(?:등학교|학교|등)?\s*([1-6])/);
  return match ? ({ 초: 0, 중: 10, 고: 20 }[match[1]] ?? 30) + Number(match[2]) : 100;
}
export function rosterGroups(rows: StudentRow[], sort: RosterSort, scope: RosterScope): RosterGroup[] {
  const unique = Array.from(new Map(rows.map(row => [row.id, row])).values());
  const byName = (a: StudentRow, b: StudentRow) => collator.compare(a.name, b.name);
  if (sort === "class") {
    const groups = new Map<string, RosterGroup>();
    for (const student of unique) {
      const classes = activeClasses(student).filter(e => (!scope.classId || e.class_id === scope.classId) && (!scope.subject || e.classes?.subject === scope.subject));
      const entries = classes.length ? classes.map(e => ({ id: e.class_id, title: e.classes!.name })) : [{ id: "unassigned", title: "수강반 미배정" }];
      for (const entry of entries) {
        if (!groups.has(entry.id)) groups.set(entry.id, { ...entry, students: [] });
        groups.get(entry.id)!.students.push(student);
      }
    }
    return Array.from(groups.values()).sort((a, b) => a.id === "unassigned" ? 1 : b.id === "unassigned" ? -1 : collator.compare(a.title, b.title)).map(g => ({ ...g, students: g.students.sort(byName) }));
  }
  const sorted = [...unique];
  if (sort !== "current") sorted.sort((a, b) => sort === "school" ? collator.compare(a.school ?? "", b.school ?? "") || byName(a, b) : sort === "grade" ? gradeRank(a.grade) - gradeRank(b.grade) || collator.compare(a.grade ?? "", b.grade ?? "") || byName(a, b) : byName(a, b));
  return sorted.length ? [{ id: "all", title: "", students: sorted }] : [];
}
export function rosterCell(student: StudentRow, field: RosterField): string {
  switch (field) {
    case "school": return student.school || "—";
    case "grade": return student.grade || "—";
    case "classes": return activeClasses(student).map(e => e.classes!.name).join("\n") || "—";
    case "status": return student.status === "active" || student.status === "재원" ? "재원" : student.status === "paused" || student.status === "휴원" ? "휴원" : "퇴원";
    case "phone": return student.phone || "—";
    case "guardianPhones": return Array.from(new Set((student.guardianPhones ?? []).filter(Boolean))).join("\n") || "—";
    default: return "";
  }
}
export function rosterColumns(options: RosterPrintOptions) { return ROSTER_FIELDS.filter(f => options.fields.includes(f.id)); }
const escape = (text: string) => text.replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
export const ROSTER_PAPER_CSS = `
.roster-paper{box-sizing:border-box;background:white;color:#262126;font-family:Arial,'Malgun Gothic','Apple SD Gothic Neo',sans-serif;line-height:1.5;font-size:10pt;padding:12mm;width:210mm;margin:auto}
.roster-paper.is-landscape{width:297mm}.roster-paper *{box-sizing:border-box}.roster-paper .roster-heading{border-bottom:2px solid #4c3544;padding-bottom:5mm;margin-bottom:6mm}.roster-paper .roster-brand{font-size:8pt;color:#76556a;letter-spacing:.12em;font-weight:700}.roster-paper h1{font-size:21pt;letter-spacing:-.05em;margin:3mm 0 4mm;line-height:1.35;overflow-wrap:anywhere}.roster-paper .roster-meta{display:flex;justify-content:space-between;gap:4mm;flex-wrap:wrap;font-size:8pt;color:#61585e}.roster-paper .roster-group{margin-top:6mm}.roster-paper h2{font-size:11pt;margin:0 0 3mm;break-after:avoid}.roster-paper h2 small{font-size:8pt;font-weight:400;color:#756b72;margin-left:3mm}.roster-paper table{width:100%;border-collapse:collapse;table-layout:fixed}.roster-paper thead{display:table-header-group}.roster-paper tr{break-inside:avoid;page-break-inside:avoid}.roster-paper th{background:#f3eff2;color:#57404f;font-size:8pt;font-weight:700}.roster-paper th,.roster-paper td{border:1px solid #d8cfd5;padding:2.6mm 2mm;text-align:left;vertical-align:middle;overflow-wrap:anywhere;white-space:pre-wrap;line-height:1.5}.roster-paper th{white-space:nowrap}.roster-paper td{min-height:10mm;font-size:9pt}.roster-paper .roster-number{width:11mm;text-align:center;color:#80747d;font-size:8pt}.roster-paper .roster-name{width:22mm;font-weight:700}.roster-paper .field-grade{width:12mm}.roster-paper .field-status{width:18mm}.roster-paper .field-check{width:14mm;text-align:center}.roster-paper .field-memo{min-width:20mm}.roster-paper .roster-check{display:inline-block;width:3.5mm;height:3.5mm;border:1px solid #9a8d96;vertical-align:middle}.roster-paper .roster-footnote{font-size:7.5pt;color:#766b73;margin:5mm 0 0;line-height:1.6}.roster-paper .roster-empty{padding:12mm 0;text-align:center;color:#756b72}
`;
export function rosterPrintHtml(rows: StudentRow[], options: RosterPrintOptions, scope: RosterScope, date: string) {
  const groups = rosterGroups(rows, options.sort, scope);
  const fields = rosterColumns(options);
  const count = new Set(rows.map(s => s.id)).size;
  const table = (g: RosterGroup) => `<section class="roster-group">${g.title ? `<h2>${escape(g.title)}<small>${g.students.length}명</small></h2>` : ""}<table><thead><tr><th class="roster-number" scope="col">번호</th><th class="roster-name" scope="col">학생명</th>${fields.map(f => `<th class="field-${f.id}" scope="col">${f.label}</th>`).join("")}</tr></thead><tbody>${g.students.map((s, i) => `<tr><td class="roster-number">${i + 1}</td><td class="roster-name">${escape(s.name)}</td>${fields.map(f => `<td class="field-${f.id}">${f.id === "check" ? '<span class="roster-check"></span>' : escape(rosterCell(s, f.id))}</td>`).join("")}</tr>`).join("")}</tbody></table></section>`;
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(options.title || "학생명단")}</title><style>${ROSTER_PAPER_CSS}@page{size:A4 ${options.orientation};margin:12mm}body{margin:0;background:#eeebee}.roster-controls{position:sticky;top:0;padding:14px 20px;background:white;border-bottom:1px solid #ded5dc;display:flex;align-items:center;gap:16px;font:14px Arial,sans-serif}.roster-controls button{border:0;border-radius:9px;background:#922d61;color:white;padding:12px 20px;cursor:pointer}.roster-controls span{color:#766675;font-size:12px}.roster-paper{margin:24px auto;box-shadow:0 5px 30px #30203015}@media print{body{background:white}.roster-controls{display:none}.roster-paper,.roster-paper.is-landscape{width:auto;margin:0;padding:0;box-shadow:none}.roster-paper thead{display:table-header-group}}</style></head><body><div class="roster-controls"><button onclick="window.print()">인쇄 · PDF 저장</button><span>PDF는 인쇄 대상에서 ‘PDF로 저장’을 선택하세요.</span></div><main class="roster-paper${options.orientation === "landscape" ? " is-landscape" : ""}"><header class="roster-heading"><div class="roster-brand">한살매 입시전문학원 · STUDENT ROSTER</div><h1>${escape(options.title || "학생명단")}</h1><div class="roster-meta"><span>${escape(scope.summary)}</span><span>총 ${count}명 · ${escape(date)}</span></div></header>${groups.map(table).join("")}<p class="roster-footnote">${options.sort === "class" ? "여러 반을 수강하는 학생은 각 반의 명단에 표시됩니다. · " : ""}한살매 · 학생 관리용 명단</p></main></body></html>`;
}
export function printStudentRoster(rows: StudentRow[], options: RosterPrintOptions, scope: RosterScope, date: string) {
  if (!rows.length) throw new Error("인쇄할 학생이 없습니다. 검색 조건을 확인해 주세요.");
  const popup = window.open("", "_blank");
  if (!popup) throw new Error("팝업이 차단되었습니다. 이 사이트의 팝업을 허용한 뒤 다시 눌러 주세요.");
  popup.opener = null;
  popup.document.open();
  popup.document.write(rosterPrintHtml(rows, options, scope, date));
  popup.document.close();
  popup.focus();
  popup.print();
}
