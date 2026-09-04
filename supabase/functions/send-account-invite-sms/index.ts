import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const digits=(value:string)=>value.replace(/\D/g,"");
const credential=(value:string|undefined)=>(value??"").trim().replace(/^(\"|')(.*)\1$/,"$2").replace(/[\s\uFEFF]+/g,"");
const namedKey=(value:string|undefined)=>{try{const keys=JSON.parse(value??"{}") as Record<string,string>;return credential(keys.default)}catch{return ""}};
const normalize=(value:string)=>value.toUpperCase().replace(/[^A-Z0-9]/g,"");
const hash=async(value:string)=>new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value)));
const hex=(value:Uint8Array)=>Array.from(value,byte=>byte.toString(16).padStart(2,"0")).join("");
const randomCode=()=>{const chars="ABCDEFGHJKLMNPQRSTUVWXYZ23456789",bytes=crypto.getRandomValues(new Uint8Array(8));return Array.from(bytes,value=>chars[value%chars.length]).join("")};
async function authorization(apiKey:string,apiSecret:string){const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const signed=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${hex(new Uint8Array(signed))}`}

type InviteRole="student"|"guardian"|"teacher";
type Input={action?:"send"|"issueAndSend"|"resend";inviteId?:string;code?:string;role?:InviteRole;studentId?:string;studentIds?:string[];recipientName?:string;recipientPhone?:string};
type Invite={id:string;role:InviteRole;student_id:string|null;code_hash:string;expires_at:string;used_at:string|null;revoked_at:string|null;recipient_name:string|null;recipient_phone:string|null};

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY");
  const apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  const bearer=request.headers.get("Authorization");
  if(!url||!anon||!apiKey||!apiSecret||!sender)return json({error:"초대 문자 발송 서버 설정을 확인해 주세요."},500);
  if(!bearer?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  let input:Input;try{input=await request.json()}catch{return json({error:"초대 정보를 확인해 주세요."},400)}
  const token=bearer.slice(7).trim(),verifier=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await verifier.auth.getUser(token);if(userError||!user)return json({error:"로그인 세션이 만료되었습니다. 다시 로그인해 주세요."},401);
  const auth=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false,autoRefreshToken:false}});
  const action=input.action==="resend"?"resend":input.action==="issueAndSend"?"issueAndSend":"send";
  const {data:prepared,error:prepareError}=await auth.rpc("admin_prepare_account_invite_sms",{p_action:action,p_invite_id:input.inviteId??null,p_code:normalize(input.code??"")||null,p_role:input.role??null,p_student_id:input.studentId??null,p_recipient_name:input.recipientName??null,p_recipient_phone:input.recipientPhone??null});
  if(prepareError||!prepared){console.error("[send-account-invite-sms] prepare failed",{action,code:prepareError?.code??null,error:prepareError?.message??null});return json({error:prepareError?.message??"초대 정보를 준비하지 못했습니다."},400)}
  const resultRow=prepared as{inviteId:string;code:string;role:InviteRole;recipientName:string;studentName:string;recipientPhone:string};
  if(resultRow.role==="guardian"&&(input.studentIds?.length??0)>1){const{error:linkError}=await auth.rpc("admin_set_guardian_invite_students",{p_invite_id:resultRow.inviteId,p_student_ids:input.studentIds});if(linkError)return json({error:linkError.message},400)}
  const code=normalize(resultRow.code),phone=digits(resultRow.recipientPhone),recipientName=resultRow.recipientName,studentName=resultRow.studentName??"";
  const formatted=`${code.slice(0,4)}-${code.slice(4)}`,roleLabel=resultRow.role==="student"?"학생":resultRow.role==="guardian"?"학부모":"선생님";
  const text=`[한살매 수업노트]\n${roleLabel} 회원가입 초대코드: ${formatted}\n아래 주소에서 '학원에서 받은 초대코드로 가입'을 선택해 주세요.\nhttps://hansalmae-student-manager.vercel.app`;
  const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone,from:sender,text,autoTypeDetect:true}})});
  const result=await response.json().catch(()=>({})) as {messageId?:string;errorMessage?:string;message?:string};
  if(!response.ok){const reason=String(result.errorMessage??result.message??"초대 문자를 발송하지 못했습니다.").slice(0,500);await auth.rpc("admin_finish_account_invite_sms",{p_invite_id:resultRow.inviteId,p_success:false,p_error:reason,p_provider_message_id:null});console.error("[send-account-invite-sms] solapi rejected",{status:response.status});return json({error:reason},502)}
  await auth.rpc("admin_finish_account_invite_sms",{p_invite_id:resultRow.inviteId,p_success:true,p_error:null,p_provider_message_id:result.messageId??null});
  return json({success:true,inviteId:resultRow.inviteId,recipientName,studentName,recipientPhone:`${phone.slice(0,3)}-****-${phone.slice(-4)}`});
});
