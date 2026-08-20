import type { Metadata, Viewport } from "next";
import "./globals.css";
import "./teacher-workspace.css";
import "./analytics.css";
import "./backup.css";
import "./bulk-import.css";
import "./bulk-account.css";
import "./continuation-polish.css";
import "./class-home-polish.css";
import "./family-kidsnote.css";
import "./family-learning-note.css";
import "./family-learning-report-feed.css";
import "./staff-report-read-status.css";
import "./learning-efficiency.css";
import "./learning-board-four-columns.css";
import "./exam-category-header.css";
import "./exam-category-modal-polish.css";
import "./menu-editor-polish.css";
import "./sidebar-inline-editor.css";
import "./class-creator-polish.css";
import "./learning-sheet-polish.css";
import "./kidsnote-final-polish.css";
import "./correction-management.css";
import "./correction-report.css";
import "./correction-management-override.css";
import "./correction-calendar-polish.css";
import "./weekly-timetable-compact.css";
import "./student-page-polish.css";
import "./class-modal-repair.css";
import { EscapeModalCloser } from "./escape-modal-closer";

export const metadata: Metadata = {
  title: "한살매 입시전문학원",
  description: "한살매입시전문학원 학생·수업·출결 통합 관리",
  manifest: "/manifest.webmanifest",
  applicationName: "한살매 입시전문학원",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "한살매",
  },
  icons: {
    icon: [
      { url: "/app-icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/app-icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
  other: { "codex-preview": "development" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#922d61",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ko"><body><EscapeModalCloser />{children}</body></html>;
}
