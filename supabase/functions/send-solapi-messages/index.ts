import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

type ClaimedMessage = { id:string; recipient_phone:string; body:string };
type SolapiItem = { messageId?:string; statusCode?:string; statusMessage?:string; customFields?:{ messageLogId?:string } };
type SolapiResponse = {
  groupInfo?:{ groupId?:string };
  messageList?:SolapiItem[];
  failedMessageList?:SolapiItem[];
};

const cleanPhone = (value:string) => value.replace(/\D/g, "");

async function authorization(apiKey:string, apiSecret:string) {
  const date = new Date().toISOString();
  const salt = crypto.randomUUID().replaceAll("-", "");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(apiSecret),
    { name:"HMAC", hash:"SHA-256" },
    false,
    ["sign"],
  );
  const signatureBytes = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(date + salt));
  const signature = Array.from(new Uint8Array(signatureBytes), byte => byte.toString(16).padStart(2, "0")).join("");
  return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers:corsHeaders });
  if (request.method !== "POST") return json({ error:"지원하지 않는 요청입니다." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("SOLAPI_API_KEY");
  const apiSecret = Deno.env.get("SOLAPI_API_SECRET");
  const sender = cleanPhone(Deno.env.get("SOLAPI_SENDER_NUMBER") ?? "");
  const bearer = request.headers.get("Authorization");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error:"문자 발송 서버 설정이 없습니다." }, 500);
  if (!apiKey || !apiSecret || !sender) return json({ error:"솔라피 API Key·Secret·발신번호 설정을 확인해 주세요." }, 500);
  if (!bearer?.startsWith("Bearer ")) return json({ error:"로그인이 필요합니다." }, 401);

  let input:{ messageIds?:string[] };
  try { input = await request.json(); } catch { return json({ error:"발송할 문자 정보를 확인해 주세요." }, 400); }
  const messageIds = [...new Set(input.messageIds ?? [])].filter(id => /^[0-9a-f-]{36}$/i.test(id));
  if (!messageIds.length) return json({ error:"발송할 문자를 선택해 주세요." }, 400);
  if (messageIds.length > 500) return json({ error:"한 번에 최대 500건까지 발송할 수 있습니다." }, 400);

  const authClient = createClient(supabaseUrl, anonKey, {
    global:{ headers:{ Authorization:bearer } },
    auth:{ persistSession:false },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth:{ persistSession:false, autoRefreshToken:false },
  });
  const { data:claimedData, error:claimError } = await authClient.rpc("staff_claim_message_delivery", { p_message_ids:messageIds });
  if (claimError) return json({ error:claimError.message }, claimError.message.includes("교직원") ? 403 : 400);
  const claimed = (claimedData ?? []) as ClaimedMessage[];
  if (!claimed.length) return json({ error:"이미 처리됐거나 발송할 수 없는 문자입니다." }, 409);

  const failAll = async (message:string) => {
    await adminClient.from("message_logs").update({ status:"failed", error_message:message, sending_at:null }).in("id", claimed.map(item => item.id));
  };

  try {
    const response = await fetch("https://api.solapi.com/messages/v4/send-many/detail", {
      method:"POST",
      headers:{
        "Authorization":await authorization(apiKey, apiSecret),
        "Content-Type":"application/json",
      },
      body:JSON.stringify({
        messages:claimed.map(item => ({
          to:cleanPhone(item.recipient_phone),
          from:sender,
          text:item.body,
          autoTypeDetect:true,
          customFields:{ messageLogId:item.id },
        })),
        strict:false,
        allowDuplicates:false,
        showMessageList:true,
      }),
    });
    const result = await response.json().catch(() => ({})) as SolapiResponse & { errorMessage?:string; message?:string };
    if (!response.ok) {
      const message = result.errorMessage ?? result.message ?? `솔라피 요청에 실패했습니다. (${response.status})`;
      await failAll(message);
      return json({ error:message }, 502);
    }

    const accepted = new Map((result.messageList ?? []).map(item => [item.customFields?.messageLogId, item]));
    const rejected = new Map((result.failedMessageList ?? []).map(item => [item.customFields?.messageLogId, item]));
    const groupId = result.groupInfo?.groupId ?? null;
    let sent = 0;
    let failed = 0;
    for (const item of claimed) {
      const success = accepted.get(item.id);
      const failure = rejected.get(item.id);
      if (success) {
        const { error:updateError } = await adminClient.from("message_logs").update({
          status:"sent",
          provider:"solapi",
          provider_message_id:success.messageId ?? null,
          provider_group_id:groupId,
          error_message:null,
          sending_at:null,
          sent_at:new Date().toISOString(),
        }).eq("id", item.id).eq("status", "sending");
        if (updateError) throw updateError;
        sent++;
      } else {
        const reason = failure?.statusMessage ?? "솔라피에서 발송 접수 결과를 확인하지 못했습니다.";
        await adminClient.from("message_logs").update({
          status:"failed",
          provider:"solapi",
          provider_message_id:failure?.messageId ?? null,
          provider_group_id:groupId,
          error_message:reason,
          sending_at:null,
        }).eq("id", item.id).eq("status", "sending");
        failed++;
      }
    }
    return json({ sent, failed, groupId });
  } catch (error) {
    const message = error instanceof Error ? error.message : "솔라피 발송 중 오류가 발생했습니다.";
    await failAll(message);
    return json({ error:message }, 502);
  }
});

