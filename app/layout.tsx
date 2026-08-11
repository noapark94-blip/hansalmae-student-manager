import type { Metadata } from "next";
import "./globals.css";
import "./analytics.css";
import "./backup.css";
import "./bulk-import.css";
import "./bulk-account.css";

export const metadata: Metadata = {
  title: "한살매 입시전문학원",
  description: "한살매입시전문학원 학생·수업·출결 통합 관리",
  other: { "codex-preview": "development" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ko"><body>{children}</body></html>;
}
