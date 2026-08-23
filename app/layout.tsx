import type { Metadata, Viewport } from "next";
import { Nanum_Pen_Script } from "next/font/google";
import "./globals.css";
import "./tuition-settlement.css";
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
import "./compact-read-status.css";
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
import "./correction-history-filter-polish.css";
import "./correction-subject-groups.css";
import "./correction-subject-tabs.css";
import "./weekly-timetable-compact.css";
import "./student-page-polish.css";
import "./class-modal-repair.css";
import "./correction-timetable-names.css";
import "./correction-direct-badges.css";
import "./student-learning-history.css";
import "./student-learning-history-fit.css";
import "./class-common-record-compact.css";
import "./class-record-compact.css";
import "./invite-signup.css";
import "./account-settings-polish.css";
import "./desktop-design-system.css";
import { EscapeModalCloser } from "./escape-modal-closer";
import { ClassEditorPermanentDelete } from "./class-editor-permanent-delete";
import { CorrectionSubjectTabs } from "./correction-subject-tabs";
import { CorrectionHubUnified } from "./correction-hub-unified";

const nanumPenScript = Nanum_Pen_Script({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-note-handwriting",
  display: "swap",
});

export const metadata: Metadata = {
  title: "한살매 수업노트",
  description: "한살매 수업·출결·학습 기록 통합 관리",
  manifest: "/manifest.webmanifest",
  applicationName: "한살매 수업노트",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "한살매 수업노트",
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
  return <html lang="ko" className={nanumPenScript.variable}><body><EscapeModalCloser /><ClassEditorPermanentDelete /><CorrectionSubjectTabs /><CorrectionHubUnified />{children}</body></html>;
}
