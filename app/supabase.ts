import { createBrowserClient } from "@supabase/ssr";

export type UserRole = "admin" | "teacher" | "student" | "guardian";

export type Profile = {
  id: string;
  role: UserRole;
  display_name: string;
};

export function createSupabaseBrowserClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) return null;
  return createBrowserClient(url, anonKey);
}
