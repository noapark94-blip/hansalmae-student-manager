import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const digits=(value:string)=>value.replace(/\D/g,"");
const credential=(value:string|undefined)=>(value??"").trim().replace(/^(\"|')(.*)\1$/,"$2").replace(/[\s\uFEFF]+/g,"");
const normalize=(value:string)=>value.toUpperCase().replace(/[^A-Z0-9]/g,"");
const hash=async(value:string)=>new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value)));
const hex=(value:Uint8Array)=>Array.from(value,byte=>byte.toString(16).padStart(2,"0")).join("");
const randomCode=()=>{const chars="ABCDEFGHJKLMNPQRSTUVWXYZ23456789",bytes=crypto.getRandomValues(new Uint8Array(8));return Array.from(bytes,value=>chars[value%chars.length]).join("")};
async function authorization(apiKey:string,apiSecret:string){const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const signed=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${hex(new Uint8Array(signed))}`}

type InviteRole="student"|"guardian"|"teacher";
type Input={action?:"send"|"issueAndSend"|"resend";inviteId?:string;code?:string;role?:InviteRole;studentId?:string;recipientName?:string;recipientPhone?:string};
type Invite={id:string;role:InviteRole;student_id:string|null;code_hash:string;expires_at:string;used_at:string|null;revoked_at:string|null;recipient_name:string|null;recipient_phone:string|null};

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  const bearer=request.headers.get("Authorization");
  if(!url||!anon||!service||!apiKey||!apiSecret||!sender)return json({error:"초대 문자 발송 서버 설정을 확인해 주세요."},500);
  if(!bearer?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  let input:Input;try{input=await request.json()}catch{return json({error:"초대 정보를 확인해 주세요."},400)}
  const auth=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false}}),admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await auth.auth.getUser();if(userError||!user)return json({error:"로그인을 다시 확인해 주세요."},401);
  const {data:actor}=await admin.from("profiles").select("role,is_active").eq("id",user.id).single();if(actor?.role!=="admin"||!actor.is_active)return json({error:"관리자만 초대 문자를 보낼 수 있습니다."},403);

  let invite:Invite|undefined,code=normalize(input.code??""),phone="",recipientName="",studentName="";
  const issuing=input.action==="issueAndSend"||input.action==="resend";
  if(issuing){
    let role=input.role,studentId=input.studentId??null;
    if(input.action==="resend"){
      const {data:previous}=await admin.from("account_invites").select("id,role,student_id,recipient_name,recipient_phone,used_at").eq("id",input.inviteId??"").single();
      if(!previous)return json({error:"재발송할 초대 내역을 찾지 못했습니다."},404);
      if(previous.used_at)return json({error:"이미 가입을 완료한 대상입니다."},400);
      role=previous.role as InviteRole;studentId=previous.student_id;input.recipientName=previous.recipient_name??undefined;input.recipientPhone=previous.recipient_phone??undefined;
    }
    if(!role||!["student","guardian","teacher"].includes(role))return json({error:"학생·학부모·선생님 중 대상을 선택해 주세요."},400);
    if(role==="student"||role==="guardian"){
      const {data:student}=await admin.from("students").select("id,name,phone,profile_id,status").eq("id",studentId??"").single();
      if(!student||!["active","재원"].includes(String(student.status)))return json({error:"재원 학생을 선택해 주세요."},400);
      studentName=student.name;recipientName=student.name;
      if(role==="student"){
        if(student.profile_id)return json({error:"이미 학생 계정 가입을 완료했습니다."},400);
        phone=digits(String(student.phone??""));
      }else{
        const {data:links}=await admin.from("student_guardians").select("guardians(name,phone,profile_id)").eq("student_id",student.id).order("is_primary",{ascending:false}).limit(1);
        const guardian=(Array.isArray(links?.[0]?.guardians)?links?.[0]?.guardians[0]:links?.[0]?.guardians) as {name?:string;phone?:string;profile_id?:string|null}|undefined;
        if(guardian?.profile_id)return json({error:"이미 학부모 계정 가입을 완료했습니다."},400);
        phone=digits(String(guardian?.phone??""));recipientName=guardian?.name||`${student.name} 학부모`;
      }
    }else{
      recipientName=String(input.recipientName??"").trim();phone=digits(String(input.recipientPhone??""));
      if(!recipientName)return json({error:"선생님 이름을 입력해 주세요."},400);
    }
    if(phone.length<10)return json({error:"발송할 휴대전화 번호를 확인해 주세요."},400);
    const now=new Date().toISOString();
    if(input.action==="resend"&&input.inviteId)await admin.from("account_invites").update({revoked_at:now}).eq("id",input.inviteId).is("used_at",null);
    if(role==="student"||role==="guardian")await admin.from("account_invites").update({revoked_at:now}).eq("role",role).eq("student_id",studentId).is("used_at",null).is("revoked_at",null);
    for(let attempt=0;attempt<5;attempt++){
      code=randomCode();
      const {data:created,error:createError}=await admin.from("account_invites").insert({code_hash:`\\x${hex(await hash(code))}`,code_hint:code.slice(-4),role,student_id:role==="teacher"?null:studentId,created_by:user.id,expires_at:new Date(Date.now()+14*86400000).toISOString(),recipient_name:recipientName,recipient_phone:phone}).select("id,role,student_id,code_hash,expires_at,used_at,revoked_at,recipient_name,recipient_phone").single();
      if(!createError&&created){invite=created as Invite;break}
    }
    if(!invite)return json({error:"새 초대코드를 발급하지 못했습니다. 다시 시도해 주세요."},500);
  }else{
    if(code.length!==8)return json({error:"초대코드를 확인해 주세요."},400);
    const {data:found,error:inviteError}=await admin.from("account_invites").select("id,role,student_id,code_hash,expires_at,used_at,revoked_at,recipient_name,recipient_phone").eq("id",input.inviteId??"").single();invite=found as Invite|undefined;
    if(inviteError||!invite||invite.used_at||invite.revoked_at||new Date(invite.expires_at)<=new Date())return json({error:"사용 가능한 초대코드를 찾을 수 없습니다."},404);
    if(String(invite.code_hash??"").replace(/^\\x/,"").toLowerCase()!==hex(await hash(code)))return json({error:"초대코드가 일치하지 않습니다."},400);
    const {data:student}=await admin.from("students").select("name,phone").eq("id",invite.student_id).single();studentName=String(student?.name??"");recipientName=invite.recipient_name||studentName;
    if(invite.role==="student")phone=digits(invite.recipient_phone||String(student?.phone??""));
    else if(invite.role==="guardian"){
      const {data:links}=await admin.from("student_guardians").select("guardians(name,phone)").eq("student_id",invite.student_id).order("is_primary",{ascending:false}).limit(1);
      const guardian=(Array.isArray(links?.[0]?.guardians)?links?.[0]?.guardians[0]:links?.[0]?.guardians) as {name?:string;phone?:string}|undefined;
      phone=digits(invite.recipient_phone||String(guardian?.phone??""));recipientName=invite.recipient_name||guardian?.name||`${studentName} 학부모`;
    }else{phone=digits(invite.recipient_phone??"");recipientName=invite.recipient_name??"선생님"}
    if(phone.length<10)return json({error:"발송할 휴대전화 번호를 확인해 주세요."},400);
  }

  const {data:attemptRow}=await admin.from("account_invites").select("sms_attempts").eq("id",invite.id).single();
  await admin.from("account_invites").update({recipient_name:recipientName,recipient_phone:phone,sms_attempts:Number(attemptRow?.sms_attempts??0)+1,sms_last_error:null}).eq("id",invite.id);
  const formatted=`${code.slice(0,4)}-${code.slice(4)}`,roleLabel=invite.role==="student"?"학생":invite.role==="guardian"?"학부모":"선생님";
  const text=`[한살매 수업노트]\n${roleLabel} 회원가입 초대코드: ${formatted}\n아래 주소에서 '학원에서 받은 초대코드로 가입'을 선택해 주세요.\nhttps://hansalmae-student-manager.vercel.app`;
  const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone,from:sender,text,autoTypeDetect:true}})});
  const result=await response.json().catch(()=>({})) as {messageId?:string;errorMessage?:string;message?:string};
  if(!response.ok){const reason=String(result.errorMessage??result.message??"초대 문자를 발송하지 못했습니다.").slice(0,500);await admin.from("account_invites").update({sms_last_error:reason}).eq("id",invite.id);console.error("[send-account-invite-sms] solapi rejected",{status:response.status});return json({error:reason},502)}
  await admin.from("account_invites").update({sms_sent_at:new Date().toISOString(),sms_last_error:null,sms_provider_message_id:result.messageId??null}).eq("id",invite.id);
  return json({success:true,inviteId:invite.id,recipientName,studentName,recipientPhone:`${phone.slice(0,3)}-****-${phone.slice(-4)}`});
});
