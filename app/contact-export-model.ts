import type { StudentRow } from "./supabase";
export type ContactStudent = Pick<StudentRow, "id" | "name" | "school" | "grade" | "phone" | "guardianPhones" | "status">;
export type ContactMode = "both" | "student" | "guardian";
export type ExportContact = { name: string; phone: string; kind: "student" | "guardian" };
export function contactName(student: ContactStudent) {
  const school = (student.school || "").trim().replace(/초등학교$/, "초").replace(/중학교$/, "중").replace(/고등학교$/, "고");
  const grade = (student.grade || "").trim();
  const match = /^(초|중|고)(?:등학교|학교|등)?\s*([1-6])(?:학년)?$/.exec(grade);
  const shortGrade = match ? school.endsWith(match[1]) ? match[2] : `${match[1]}${match[2]}` : grade.replace(/학년$/, "");
  return [school + shortGrade, student.name.trim()].filter(Boolean).join(" ");
}
export function contactPhone(raw: string): string | null {
  if (!/^[+\d\s().-]+$/.test(raw)) return null;
  let number = raw.replace(/[\s().-]/g, "");
  if (number.startsWith("+82")) number = "0" + number.slice(3).replace(/^0/, "");
  if (/^0\d{8,10}$/.test(number) || /^\+[1-9]\d{7,14}$/.test(number)) return number;
  return null;
}
export function exportContacts(rows: ContactStudent[], mode: ContactMode = "both") {
  const groups = new Map<string, { phone: string; kind: ExportContact["kind"]; names: Set<string> }>();
  let skipped = 0, merged = 0;
  for (const row of new Map(rows.map(r => [r.id, r])).values()) {
    const entries: [ExportContact["kind"], string][] = [];
    if (mode !== "guardian" && row.phone?.trim()) entries.push(["student", row.phone]);
    if (mode !== "student") for (const phone of row.guardianPhones || []) if (phone?.trim()) entries.push(["guardian", phone]);
    for (const [kind, raw] of entries) {
      const phone = contactPhone(raw);
      if (!phone) { skipped++; continue; }
      const key = `${kind}:${phone}`;
      if (!groups.has(key)) groups.set(key, { phone, kind, names: new Set() }); else merged++;
      groups.get(key)!.names.add(contactName(row));
    }
  }
  const contacts = [...groups.values()].map(g => ({ phone: g.phone, kind: g.kind, name: [...g.names].sort((a,b) => a.localeCompare(b,"ko")).join("·") + (g.kind === "guardian" ? " 학부모" : "") })).sort((a,b) => a.name.localeCompare(b.name,"ko") || a.phone.localeCompare(b.phone));
  return { contacts, skipped, merged };
}
const escape = (value: string) => value.replace(/\\/g,"\\\\").replace(/\r\n|\r|\n/g,"\\n").replace(/;/g,"\\;").replace(/,/g,"\\,");
// Fold at 75 UTF-8 bytes without splitting a multibyte character.
export function foldVCardLine(value: string) {
  const encoder = new TextEncoder(); let result = "", size = 0;
  for (const ch of value) { const bytes = encoder.encode(ch).length; if (size + bytes > 75) { result += "\r\n "; size = 1; } result += ch; size += bytes; }
  return result;
}
export function contactsVCard(contacts: ExportContact[]) {
  return contacts.map(c => ["BEGIN:VCARD", "VERSION:3.0", `UID:hsm-${c.kind}-${c.phone.replace(/\+/g, "")}`, `FN:${escape(c.name)}`, `N:${escape(c.name)};;;;`, `TEL;TYPE=VOICE:${c.phone}`, "END:VCARD"].map(foldVCardLine).join("\r\n")).join("\r\n") + (contacts.length ? "\r\n" : "");
}
