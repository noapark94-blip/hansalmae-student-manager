import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const digits=(value:string)=>value.replace(/\D/g,"");
const credential=(value:string|undefined)=>(value??"").trim().replace(/^(\"|')(.*)\1$/, "$2").replace(/[\s\uFEFF]+/g,"");
const temporaryPassword=()=>{const chars="ABCDEFGHJKLMNPQRSTUVWXYZ23456789";return Array.from(crypto.getRandomValues(new Uint32Array(8)),value=>chars[value%chars.length]).join("")};
async function authorization(apiKey:string,apiSecret:string){const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const signed=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));const signature=Array.from(new Uint8Array(signed),byte=>byte.toString(16).padStart(2,"0")).join("");return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`}

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  const bearer=request.headers.get("Authorization");
  if(!url||!anon||!service||!apiKey||!apiSecret||!sender)return json({error:"비밀번호 문자 발송 서버 설정을 확인해 주세요."},500);
  if(!bearer?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  let input:{requestId?:string};try{input=await request.json()}catch{return json({error:"요청 정보를 확인해 주세요."},400)}
  const authClient=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false}});
  const adminClient=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await authClient.auth.getUser();
  if(userError||!user)return json({error:"로그인을 다시 확인해 주세요."},401);
  const {data:actor}=await adminClient.from("profiles").select("role,is_active").eq("id",user.id).single();
  if(actor?.role!=="admin"||!actor.is_active)return json({error:"관리자만 임시 비밀번호를 발급할 수 있습니다."},403);
  const {data:requestRow,error:requestError}=await adminClient.from("password_reset_requests").select("id,profile_id,status,profiles(display_name,phone)").eq("id",input.requestId??"").eq("status","pending").single();
  if(requestError||!requestRow)return json({error:"처리할 비밀번호 요청을 찾을 수 없습니다."},404);
  const profile=(Array.isArray(requestRow.profiles)?requestRow.profiles[0]:requestRow.profiles) as {display_name?:string;phone?:string}|null;
  const [{data:student},{data:guardian}]=await Promise.all([adminClient.from("students").select("phone").eq("profile_id",requestRow.profile_id).limit(1).maybeSingle(),adminClient.from("guardians").select("phone").eq("profile_id",requestRow.profile_id).limit(1).maybeSingle()]);
  const phone=digits(profile?.phone??student?.phone??guardian?.phone??"");if(phone.length<10)return json({error:"계정에 등록된 연락처를 확인해 주세요."},400);
  const password=temporaryPassword();
  const {error:updateError}=await adminClient.auth.admin.updateUserById(requestRow.profile_id,{password});
  if(updateError)return json({error:"임시 비밀번호를 적용하지 못했습니다."},500);
  await adminClient.from("profiles").update({must_change_password:true}).eq("id",requestRow.profile_id);
  const text=`[한살매 수업노트]\n임시 비밀번호: ${password}\n로그인 후 새 비밀번호로 반드시 변경해 주세요.\nhttps://hansalmae-student-manager.vercel.app`;
  const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone,from:sender,text,autoTypeDetect:true}})});
  if(!response.ok){console.error("[admin-reset-password] solapi rejected",{status:response.status});return json({error:"임시 비밀번호는 변경됐지만 문자를 보내지 못했습니다. 다시 발급해 주세요."},502)}
  const {error:completeError}=await adminClient.rpc("internal_complete_password_reset",{p_request_id:requestRow.id,p_processed_by:user.id});
  if(completeError)return json({error:"문자는 발송됐지만 요청 완료 처리를 하지 못했습니다."},500);
  return json({success:true,recipientPhone:`${phone.slice(0,3)}-****-${phone.slice(-4)}`});
});
