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
  enrollments: {
    status: "active" | "paused" | "completed";
    classes: { subject: string } | null;
  }[];
};

export function createSupabaseBrowserClient() {
  const url = import.meta.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = import.meta.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) return null;
  return createBrowserClient(url, anonKey);
}
