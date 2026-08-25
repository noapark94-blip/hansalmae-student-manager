import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const digits=(value:string)=>value.replace(/\D/g,"");
const credential=(value:string|undefined)=>(value??"").trim().replace(/^(\"|')(.*)\1$/,"$2").replace(/[\s\uFEFF]+/g,"");
const normalize=(value:string)=>value.toUpperCase().replace(/[^A-Z0-9]/g,"");
const hash=async(value:string)=>new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value)));
async function authorization(apiKey:string,apiSecret:string){const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const signed=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));const signature=Array.from(new Uint8Array(signed),byte=>byte.toString(16).padStart(2,"0")).join("");return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`}

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  const bearer=request.headers.get("Authorization");
  if(!url||!anon||!service||!apiKey||!apiSecret||!sender)return json({error:"초대 문자 발송 서버 설정을 확인해 주세요."},500);
  if(!bearer?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  let input:{inviteId?:string;code?:string};try{input=await request.json()}catch{return json({error:"초대 정보를 확인해 주세요."},400)}
  const code=normalize(input.code??"");if(code.length!==8)return json({error:"초대코드를 확인해 주세요."},400);
  const auth=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false}}),admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await auth.auth.getUser();if(userError||!user)return json({error:"로그인을 다시 확인해 주세요."},401);
  const {data:actor}=await admin.from("profiles").select("role,is_active").eq("id",user.id).single();if(actor?.role!=="admin"||!actor.is_active)return json({error:"관리자만 초대 문자를 보낼 수 있습니다."},403);
  const {data:invite,error:inviteError}=await admin.from("account_invites").select("id,role,student_id,code_hash,expires_at,used_at,revoked_at").eq("id",input.inviteId??"").single();
  if(inviteError||!invite||invite.used_at||invite.revoked_at||new Date(invite.expires_at)<=new Date())return json({error:"사용 가능한 초대코드를 찾을 수 없습니다."},404);
  const actual=await hash(code),actualHex=Array.from(actual,value=>value.toString(16).padStart(2,"0")).join(""),expectedHex=String(invite.code_hash??"").replace(/^\\x/,"").toLowerCase();if(expectedHex!==actualHex)return json({error:"초대코드가 일치하지 않습니다."},400);
  let phone="",recipientName="";
  const {data:student}=await admin.from("students").select("name,phone").eq("id",invite.student_id).single();recipientName=String(student?.name??"");
  if(invite.role==="student")phone=digits(String(student?.phone??""));
  else if(invite.role==="guardian"){
    const {data:links}=await admin.from("student_guardians").select("guardians(name,phone)").eq("student_id",invite.student_id).order("is_primary",{ascending:false}).limit(1);
    const guardian=(Array.isArray(links?.[0]?.guardians)?links?.[0]?.guardians[0]:links?.[0]?.guardians) as {name?:string;phone?:string}|undefined;
    phone=digits(String(guardian?.phone??""));recipientName=guardian?.name||`${recipientName} 학부모`;
  } else return json({error:"학생·학부모 초대만 문자로 보낼 수 있습니다."},400);
  if(phone.length<10)return json({error:`${invite.role==="student"?"학생":"학부모"} 연락처가 등록되어 있지 않습니다.`},400);
  const formatted=`${code.slice(0,4)}-${code.slice(4)}`,roleLabel=invite.role==="student"?"학생":"학부모";
  const text=`[한살매 수업노트]\n${roleLabel} 회원가입 초대코드: ${formatted}\n아래 주소에서 '학원에서 받은 초대코드로 가입'을 선택해 주세요.\nhttps://hansalmae-student-manager.vercel.app`;
  const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone,from:sender,text,autoTypeDetect:true}})});
  if(!response.ok){console.error("[send-account-invite-sms] solapi rejected",{status:response.status});return json({error:"초대 문자를 발송하지 못했습니다."},502)}
  return json({success:true,recipientName,recipientPhone:`${phone.slice(0,3)}-****-${phone.slice(-4)}`});
});
