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
  return <html lang="ko"><body>{children}</body></html>;
}
