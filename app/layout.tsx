import type { Metadata } from "next";
import "./globals.css";
import "./analytics.css";

export const metadata: Metadata = {
  title: "한살매 학생관리",
  description: "한살매입시전문학원 학생·수업·출결 통합 관리",
  other: { "codex-preview": "development" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ko"><body>{children}</body></html>;
}
