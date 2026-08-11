import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "지원하지 않는 요청입니다." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = request.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error: "서버 계정 생성 설정이 없습니다." }, 500);
  if (!authorization?.startsWith("Bearer ")) return json({ error: "로그인이 필요합니다." }, 401);

  const token = authorization.slice(7);
  const authClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await authClient.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "로그인 정보를 확인할 수 없습니다." }, 401);

  const { data: actor } = await adminClient.from("profiles").select("role,is_active").eq("id", userData.user.id).maybeSingle();
  if (!actor?.is_active || actor.role !== "admin") return json({ error: "관리자만 로그인 계정을 만들 수 있습니다." }, 403);

  let input: { email?:string; password?:string; displayName?:string; phone?:string|null; role?:string; studentId?:string|null; childIds?:string[] };
  try { input = await request.json(); } catch { return json({ error: "입력 내용을 확인해 주세요." }, 400); }
  const email = input.email?.trim().toLowerCase();
  const displayName = input.displayName?.trim();
  const roles = ["admin", "teacher", "student", "guardian"];
  if (!email || !/^\S+@\S+\.\S+$/.test(email)) return json({ error: "올바른 이메일을 입력해 주세요." }, 400);
  if (!input.password || input.password.length < 8) return json({ error: "임시 비밀번호는 8자 이상 입력해 주세요." }, 400);
  if (!displayName) return json({ error: "표시 이름을 입력해 주세요." }, 400);
  if (!input.role || !roles.includes(input.role)) return json({ error: "계정 역할을 선택해 주세요." }, 400);
  if (input.role === "guardian" && !input.phone?.trim()) return json({ error: "학부모 연락처를 입력해 주세요." }, 400);

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password: input.password,
    email_confirm: true,
    user_metadata: { display_name: displayName, role: input.role },
  });
  if (createError || !created.user) return json({ error: createError?.message ?? "로그인 계정을 만들지 못했습니다." }, 400);

  const { error: settingsError } = await authClient.rpc("admin_save_account_settings", {
    p_profile_id: created.user.id,
    p_display_name: displayName,
    p_phone: input.phone?.trim() || null,
    p_role: input.role,
    p_is_active: true,
    p_student_id: input.role === "student" ? input.studentId || null : null,
    p_child_ids: input.role === "guardian" ? input.childIds ?? [] : [],
  });
  if (settingsError) {
    await adminClient.auth.admin.deleteUser(created.user.id);
    return json({ error: settingsError.message }, 400);
  }

  return json({ id: created.user.id, email });
});
