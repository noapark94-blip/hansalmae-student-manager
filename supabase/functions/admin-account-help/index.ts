import { createClient } from "npm:@supabase/supabase-js@2";
const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const digits=(value:string)=>value.replace(/\D/g,"");
const credential=(value:string|undefined)=>(value??"").trim().replace(/^(\"|')(.*)\1$/, "$2").replace(/[\s\uFEFF]+/g,"");
const password=()=>{const chars="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$";return Array.from(crypto.getRandomValues(new Uint32Array(10)),value=>chars[value%chars.length]).join("")};
async function authorization(apiKey:string,apiSecret:string){const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const signed=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));const signature=Array.from(new Uint8Array(signed),byte=>byte.toString(16).padStart(2,"0")).join("");return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`}
Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),anon=Deno.env.get("SUPABASE_ANON_KEY"),apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  const bearer=request.headers.get("Authorization");if(!url||!service||!anon||!apiKey||!apiSecret||!sender)return json({error:"서버 설정을 확인해 주세요."},500);if(!bearer?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}}),token=bearer.slice(7).trim();
  const{data:{user},error:userError}=await admin.auth.getUser(token);if(userError||!user)return json({error:"로그인 세션이 만료되었습니다. 다시 로그인해 주세요."},401);
  const authClient=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false,autoRefreshToken:false}});
  const[{data:actor,error:actorError},{data:actorRole,error:roleError}]=await Promise.all([
    admin.from("profiles").select("role,is_active").eq("id",user.id).maybeSingle(),
    authClient.rpc("current_user_role")
  ]);
  const isAdmin=(actor?.role==="admin"&&actor.is_active===true)||actorRole==="admin";
  if(!isAdmin){console.error("[admin-account-help] admin authorization failed",{userId:user.id,profileRole:actor?.role??null,isActive:actor?.is_active??null,actorError:actorError?.message??null,rpcRole:actorRole??null,roleError:roleError?.message??null});return json({error:"관리자 권한을 확인하지 못했습니다. 다시 로그인한 뒤 시도해 주세요."},403)}
  let input:{action?:"approve"|"reject";requestId?:string;profileId?:string};try{input=await request.json()}catch{return json({error:"요청 정보를 확인해 주세요."},400)}
  const{data:help}=await admin.from("account_help_requests").select("*").eq("id",input.requestId??"").eq("status","pending").maybeSingle();if(!help)return json({error:"처리할 요청을 찾지 못했습니다."},404);
  if(input.action==="reject"){await admin.from("account_help_requests").update({status:"rejected",processed_at:new Date().toISOString(),processed_by:user.id}).eq("id",help.id).eq("status","pending");return json({success:true})}
  if(input.action!=="approve"||!input.profileId)return json({error:"확인된 계정을 선택해 주세요."},400);
  const{data:profile}=await admin.from("profiles").select("id,display_name,role").eq("id",input.profileId).eq("is_active",true).maybeSingle();if(!profile)return json({error:"처리할 계정을 찾지 못했습니다."},404);
  const phone=digits(help.reachable_phone),temporary=password();if(phone.length<10)return json({error:"현재 연락 가능한 번호를 확인해 주세요."},400);
  const{error:updateError}=await admin.auth.admin.updateUserById(profile.id,{password:temporary});if(updateError)return json({error:"임시 비밀번호를 적용하지 못했습니다."},500);
  await admin.from("profiles").update({phone:help.reachable_phone,must_change_password:true}).eq("id",profile.id);
  if(profile.role==="student")await admin.from("students").update({phone:help.reachable_phone}).eq("profile_id",profile.id);
  if(profile.role==="guardian")await admin.from("guardians").update({phone:help.reachable_phone}).eq("profile_id",profile.id);
  const text=`[한살매 수업노트]\n계정 확인이 완료되었습니다.\n임시 비밀번호: ${temporary}\n로그인 후 새 비밀번호로 변경해 주세요.\nhttps://hansalmae-student-manager.vercel.app`;
  const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone,from:sender,text,autoTypeDetect:true}})});if(!response.ok)return json({error:"연락처와 비밀번호는 변경됐지만 문자를 보내지 못했습니다. 계정 설정에서 다시 처리해 주세요."},502);
  await admin.from("account_help_requests").update({profile_id:profile.id,status:"completed",processed_at:new Date().toISOString(),processed_by:user.id}).eq("id",help.id).eq("status","pending");
  return json({success:true,recipientPhone:`${phone.slice(0,3)}-****-${phone.slice(-4)}`});
});
