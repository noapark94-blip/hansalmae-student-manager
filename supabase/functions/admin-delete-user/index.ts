import { createClient } from "npm:@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return response("로그인이 필요합니다.",401);
    const token=auth.slice(7);
    const caller = createClient(url, anon, { global: { headers: { Authorization: auth } },auth:{persistSession:false} });
    const { data: { user },error:userError } = await caller.auth.getUser(token);
    if (userError||!user) return response("로그인 정보를 확인할 수 없습니다.",401);
    const {data:role,error:roleError}=await caller.rpc("current_user_role");
    if(roleError){console.error("[admin-delete-user] role lookup failed",{callerId:user.id,error:roleError.message});return response("관리자 권한을 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.",500)}
    if(role!=="admin")return response("관리자만 계정을 삭제할 수 있습니다.",403);
    const admin = createClient(url, service,{auth:{persistSession:false,autoRefreshToken:false}});
    const { profileId } = await req.json() as { profileId?: string };
    if (!profileId) throw new Error("삭제할 계정을 선택해 주세요.");
    if (profileId === user.id) throw new Error("현재 로그인한 관리자 계정은 삭제할 수 없습니다.");
    const {error:prepareError}=await admin.rpc("admin_prepare_guardian_account_deletion",{p_profile_id:profileId});
    if(prepareError){console.error("[admin-delete-user] guardian cleanup preparation failed",{callerId:user.id,targetId:profileId,error:prepareError.message});return response("학부모 연결 정보를 안전하게 정리하지 못했습니다. 잠시 후 다시 시도해 주세요.",500)}
    const { error } = await admin.auth.admin.deleteUser(profileId);
    if (error){console.error("[admin-delete-user] deletion failed",{callerId:user.id,targetId:profileId,error:error.message});return response("연결된 수업·출결 등 보존할 기록이 있어 완전 삭제할 수 없습니다. 계정 설정에서 로그인을 비활성화해 주세요.",409)}
    return new Response(JSON.stringify({ ok: true }), { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (error) {
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "계정을 삭제하지 못했습니다." }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
  }
});

function response(error:string,status:number){return new Response(JSON.stringify({error}),{status,headers:{...cors,"Content-Type":"application/json"}})}
