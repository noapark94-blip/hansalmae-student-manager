import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: { user } } = await caller.auth.getUser();
    if (!user) throw new Error("로그인이 필요합니다.");
    const admin = createClient(url, service);
    const { data: profile } = await admin.from("profiles").select("role").eq("id", user.id).single();
    if (profile?.role !== "admin") throw new Error("관리자만 계정을 삭제할 수 있습니다.");
    const { profileId } = await req.json() as { profileId?: string };
    if (!profileId) throw new Error("삭제할 계정을 선택해 주세요.");
    if (profileId === user.id) throw new Error("현재 로그인한 관리자 계정은 삭제할 수 없습니다.");
    const { error } = await admin.auth.admin.deleteUser(profileId);
    if (error) return new Response(JSON.stringify({ error: "연결된 수업·출결 등 보존할 기록이 있어 완전 삭제할 수 없습니다. 계정 설정에서 로그인을 비활성화해 주세요." }), { status: 409, headers: { ...cors, "Content-Type": "application/json" } });
    return new Response(JSON.stringify({ ok: true }), { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "계정을 삭제하지 못했습니다." }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
  }
});
