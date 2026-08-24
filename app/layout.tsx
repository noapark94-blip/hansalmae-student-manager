import type { Metadata, Viewport } from "next";
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
import "./mobile-design-system.css";
import "./family-mobile-app.css";
import "./staff-mobile-app.css";
import { EscapeModalCloser } from "./escape-modal-closer";
import { ClassEditorPermanentDelete } from "./class-editor-permanent-delete";
import { CorrectionSubjectTabs } from "./correction-subject-tabs";
import { CorrectionHubUnified } from "./correction-hub-unified";

export const metadata: Metadata = {
  metadataBase: new URL("https://hansalmae-student-manager.vercel.app"),
  title: "한살매 수업노트",
  description: "학생·학부모·선생님을 위한 수업, 시간표, 출결 및 학습 기록 서비스",
  manifest: "/manifest.webmanifest",
  applicationName: "한살매 수업노트",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "한살매노트",
  },
  icons: {
    icon: [
      { url: "/app-icon-192-v2.png", sizes: "192x192", type: "image/png" },
      { url: "/app-icon-512-v2.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon-v2.png", sizes: "180x180", type: "image/png" }],
  },
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    locale: "ko_KR",
    url: "/",
    siteName: "한살매 수업노트",
    title: "한살매 수업노트",
    description: "학생·학부모·선생님을 위한 수업, 시간표, 출결 및 학습 기록 서비스",
    images: [{ url: "/og-hansalmae-note.png", width: 1200, height: 630, alt: "한살매 수업노트" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "한살매 수업노트",
    description: "학생·학부모·선생님을 위한 수업, 시간표, 출결 및 학습 기록 서비스",
    images: ["/og-hansalmae-note.png"],
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
  return <html lang="ko"><body><EscapeModalCloser /><ClassEditorPermanentDelete /><CorrectionSubjectTabs /><CorrectionHubUnified />{children}</body></html>;
}
