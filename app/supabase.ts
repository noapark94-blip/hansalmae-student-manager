import { createBrowserClient } from "@supabase/ssr";

export type UserRole = "admin" | "teacher" | "student" | "guardian";

export type Profile = {
  id: string;
  role: UserRole;
  display_name: string;
};

export type StudentRow = {
  id: string;
  name: string;
  school: string | null;
  grade: string | null;
  status: string;
  attendanceRate?: number | null;
  attendanceChecked?: number;
  enrollments: {
    class_id: string;
    status: "active" | "paused" | "completed";
    classes: { name: string; subject: string } | null;
  }[];
};

export type AcademyClass = {
  id: string;
  name: string;
  subject: string;
  subject_id?: string | null;
  room: string | null;
  color: string;
  active: boolean;
};

export function createSupabaseBrowserClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) return null;
  return createBrowserClient(url, anonKey);
}
