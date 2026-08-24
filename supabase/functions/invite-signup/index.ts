import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
const normalizeCode = (value: string) => value.toUpperCase().replace(/[^A-Z0-9]/g, "");
const hashCode = async (code: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(code)));
const toHex = (bytes: Uint8Array) => `\\x${[...bytes].map((value) => value.toString(16).padStart(2, "0")).join("")}`;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "지원하지 않는 요청입니다." }, 405);
  const url = Deno.env.get("SUPABASE_URL"),
    service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !service) return json({ error: "회원가입 서버 설정이 없습니다." }, 500);
  let input: {
    action?: string;
    code?: string;
    email?: string;
    password?: string;
    displayName?: string;
    phone?: string;
  };
  try {
    input = await request.json();
  } catch {
    return json({ error: "입력 내용을 확인해 주세요." }, 400);
  }
  const code = normalizeCode(input.code ?? "");
  if (code.length !== 8) return json({ error: "8자리 초대코드를 입력해 주세요." }, 400);
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const hash = await hashCode(code),
    hex = toHex(hash);
  const { data: invite, error: inviteError } = await admin.rpc("check_account_invite", { p_code_hash: hex });
  if (inviteError) return json({ error: "초대코드를 확인하지 못했습니다." }, 500);
  if (!invite) return json({ error: "초대코드가 올바르지 않거나 만료되었습니다." }, 400);
  if (input.action === "check")
    return json({
      valid: true,
      role: invite.role,
      targetName: invite.targetName,
    });
  const email = input.email?.trim().toLowerCase(),
    name = invite.role === "student" ? String(invite.targetName ?? "").trim() : input.displayName?.trim(),
    phone = input.phone?.trim() ?? "";
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "올바른 이메일을 입력해 주세요." }, 400);
  if (!input.password || input.password.length < 8) return json({ error: "비밀번호는 8자 이상 입력해 주세요." }, 400);
  if (!name) return json({ error: "이름을 입력해 주세요." }, 400);
  if (invite.role === "guardian" && !phone) return json({ error: "학부모 연락처를 입력해 주세요." }, 400);
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password: input.password,
    email_confirm: true,
    user_metadata: { display_name: name },
  });
  if (createError || !created.user)
    return json(
      {
        error: createError?.message === "A user with this email address has already been registered" ? "이미 가입된 이메일입니다." : (createError?.message ?? "계정을 만들지 못했습니다."),
      },
      400,
    );
  const { data: claimed, error: claimError } = await admin.rpc("claim_account_invite", {
    p_code_hash: hex,
    p_profile_id: created.user.id,
    p_display_name: name,
    p_phone: phone || null,
  });
  if (claimError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return json({ error: claimError.message }, 400);
  }
  return json({ success: true, ...claimed });
});
