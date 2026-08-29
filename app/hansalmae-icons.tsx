import type { ReactNode } from "react";
import type { View } from "./page";

type IconName = "home" | "students" | "classes" | "calendar" | "timetable" | "edit" | "bus" | "chat" | "notice" | "bell" | "wallet" | "settings" | "chart" | "backup" | "shield" | "user" | "plus" | "check" | "refresh" | "book" | "exam" | "menu";

const paths: Record<IconName, ReactNode> = {
  home: <><path d="M3.5 10.5 12 3.8l8.5 6.7"/><path d="M5.8 9.3v10h12.4v-10"/><path d="M9.4 19.3v-5.8h5.2v5.8"/></>,
  students: <><circle cx="8.2" cy="8.2" r="2.8"/><circle cx="15.8" cy="8.2" r="2.8"/><path d="M2.8 19c.25-3.7 2.05-5.55 5.4-5.55 1.55 0 2.8.4 3.8 1.2"/><path d="M21.2 19c-.25-3.7-2.05-5.55-5.4-5.55-1.55 0-2.8.4-3.8 1.2"/></>,
  classes: <><rect x="4" y="4.5" width="16" height="15" rx="2.2"/><path d="M8 8.5h8M8 12h8M8 15.5h5"/></>,
  calendar: <><rect x="3.8" y="5.5" width="16.4" height="14.2" rx="2.2"/><path d="M7.5 3.5v4M16.5 3.5v4M4 9.5h16"/><path d="M8 13h.01M12 13h.01M16 13h.01M8 16.5h.01M12 16.5h.01"/></>,
  timetable: <><rect x="3.5" y="4.5" width="17" height="15" rx="2.2"/><path d="M8.5 4.5v15M3.5 9.5h17M3.5 14.5h17M14.5 9.5v10"/></>,
  edit: <><path d="m5 16.5-.8 3.3 3.3-.8L18.8 7.7a2 2 0 0 0-2.8-2.8Z"/><path d="m14.8 6.1 3 3"/></>,
  bus: <><rect x="4" y="4" width="16" height="14" rx="3"/><path d="M7 8h10M7 12h10M7.5 18v2M16.5 18v2"/><circle cx="8" cy="15" r=".7"/><circle cx="16" cy="15" r=".7"/></>,
  chat: <><path d="M5 5.2h14v10.5H10l-5 3v-3H5Z"/><path d="M8.5 9h7M8.5 12h4.5"/></>,
  notice: <><path d="M5 10.5v3l3 1 7 4V5.5l-7 4Z"/><path d="M8 14.5 9.5 19"/><path d="M18 8v6"/></>,
  bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"/><path d="M10 21h4"/></>,
  wallet: <><rect x="3.5" y="6" width="17" height="13" rx="2.5"/><path d="M4.5 9h15.5M15 13h5"/><circle cx="16.5" cy="14.5" r=".6"/></>,
  settings: <><circle cx="12" cy="12" r="3"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6 18 18M18 6l-1.4 1.4M7.4 16.6 6 18"/></>,
  chart: <><path d="M4 20V5M4 20h16"/><path d="m7 16 4-4 3 2 5-6"/></>,
  backup: <><path d="M12 4v10M8.5 10.5 12 14l3.5-3.5"/><path d="M5 17.5v2h14v-2"/></>,
  shield: <><path d="M12 3.5 19 6v5.2c0 4.4-2.4 7.4-7 9.3-4.6-1.9-7-4.9-7-9.3V6Z"/><path d="m8.8 12 2 2 4.4-4.4"/></>,
  user: <><circle cx="12" cy="8" r="3.5"/><path d="M5.5 20c.5-4.2 2.7-6.3 6.5-6.3s6 2.1 6.5 6.3"/></>,
  plus: <><path d="M12 5v14M5 12h14"/></>,
  check: <><path d="m5 12 4.2 4.2L19 6.8"/></>,
  refresh: <><path d="M19 8V4l-2 2a8 8 0 1 0 2.2 8"/></>,
  book: <><path d="M4.5 5.5c3.1-.8 5.6-.2 7.5 1.7v12c-1.9-1.9-4.4-2.5-7.5-1.7Z"/><path d="M19.5 5.5c-3.1-.8-5.6-.2-7.5 1.7v12c1.9-1.9 4.4-2.5 7.5-1.7Z"/></>,
  exam: <><path d="M6 3.5h8.8L18.5 7v13.5H6Z"/><path d="M14.5 3.8v3.7h3.7M9 11h6M9 14h6M9 17h3"/><path d="m7.7 10.8.8.8 1.4-1.8"/></>,
  menu: <><path d="M5 7h14M5 12h14M5 17h14"/></>,
};

export const viewIcon: Record<View, IconName> = {
  dashboard:"home", students:"students", "bulk-import":"plus", "bulk-accounts":"user", guide:"book", "class-management":"classes", schedule:"timetable", corrections:"edit", transport:"bus", attendance:"check", makeups:"refresh", assignments:"edit", "vocabulary-tests":"exam", alimtalk:"chat", reports:"book", calendar:"calendar", grades:"chart", consultations:"chat", communications:"notice", tuition:"wallet", analytics:"chart", backup:"backup", audit:"shield", settings:"settings", "my-account":"user",
};

export function HansalmaeIcon({ name, size = 20 }: { name: IconName; size?: number }) {
  return <svg className="hansalmae-icon" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}
