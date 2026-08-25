import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const digits=(value:string)=>value.replace(/\D/g,"");
const credential=(value:string|undefined)=>(value??"").trim().replace(/^(\"|')(.*)\1$/, "$2").replace(/[\s\uFEFF]+/g,"");
const hex=(buffer:ArrayBuffer)=>Array.from(new Uint8Array(buffer),byte=>byte.toString(16).padStart(2,"0")).join("");
async function hash(value:string){return hex(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(value)))}
async function authorization(apiKey:string,apiSecret:string){const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);const signed=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${hex(signed)}`}
function code(){return String(crypto.getRandomValues(new Uint32Array(1))[0]%1_000_000).padStart(6,"0")}

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=credential(Deno.env.get("SUPABASE_URL")),anon=credential(Deno.env.get("SUPABASE_ANON_KEY")),pepper=anon;
  const apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  if(!url||!anon||!pepper||!apiKey||!apiSecret||!sender)return json({error:"문자 인증 서버 설정을 확인해 주세요."},500);
  const admin=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const matchingProfiles=async(name:string,phone:string)=>{
    const{data,error}=await admin.rpc("account_recovery_match",{p_name:name,p_phone:phone});
    if(error)throw error;
    return (data??[]) as {profile_id:string;login_id:string}[];
  };
  let input:{action?:string;purpose?:"id"|"password";name?:string;phone?:string;challengeId?:string;code?:string;password?:string;accountType?:"student"|"guardian"|"staff";registeredPhone?:string;reachablePhone?:string;reason?:"phone_changed"|"sms_unavailable"|"other"};
  try{input=await request.json()}catch{return json({error:"요청 정보를 확인해 주세요."},400)}

  if(input.action==="lookup-id"){
    const name=(input.name??"").trim(),phone=digits(input.phone??"");if(!name||phone.length<10)return json({error:"이름과 연락처를 정확히 입력해 주세요."},400);
    let matches:{profile_id:string;login_id:string}[];try{matches=await matchingProfiles(name,phone)}catch(error){console.error("[account-recovery-otp] lookup failed",error);return json({error:"계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."},500)}
    if(matches.length!==1)return json({error:"입력한 정보와 일치하는 계정을 찾지 못했습니다."},404);if(!matches[0].login_id)return json({error:"로그인 아이디를 확인하지 못했습니다."},500);return json({success:true,loginId:matches[0].login_id});
  }

  if(input.action==="help-request"){
    const requesterName=(input.name??"").trim(),reachable=digits(input.reachablePhone??"");if(!requesterName||reachable.length<10||!input.accountType||!input.reason)return json({error:"도움 요청 정보를 정확히 입력해 주세요."},400);
    const old=digits(input.registeredPhone??"");let profileId:string|null=null;const{data:profiles}=await admin.from("profiles").select("id,phone").eq("is_active",true).ilike("display_name",requesterName);
    if(old){const matched=[];for(const profile of profiles??[]){const[{data:student},{data:guardian}]=await Promise.all([admin.from("students").select("phone").eq("profile_id",profile.id).limit(1).maybeSingle(),admin.from("guardians").select("phone").eq("profile_id",profile.id).limit(1).maybeSingle()]);if(digits(profile.phone??student?.phone??guardian?.phone??"")===old)matched.push(profile)}if(matched.length===1)profileId=matched[0].id}else if(profiles?.length===1)profileId=profiles[0].id;
    const{error}=await admin.from("account_help_requests").insert({requester_name:requesterName,account_type:input.accountType,registered_phone:input.registeredPhone||null,reachable_phone:input.reachablePhone,reason:input.reason,profile_id:profileId});if(error)return json({error:"도움 요청을 등록하지 못했습니다."},500);return json({success:true});
  }

  if(input.action==="send"){
    const name=(input.name??"").trim(),phone=digits(input.phone??""),purpose=input.purpose;
    if(!name||phone.length<10||purpose!=="password")return json({error:"이름과 연락처를 정확히 입력해 주세요."},400);
    const phoneHash=await hash(`${phone}:${pepper}`);
    let matches:{profile_id:string;login_id:string}[];try{matches=await matchingProfiles(name,phone)}catch(error){console.error("[account-recovery-otp] recovery lookup failed",error);return json({error:"계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."},500)}
    const target=matches.length===1?matches[0]:null,otp=code();
    if(!target)return json({error:"입력한 정보와 일치하는 계정을 찾지 못했습니다."},404);
    const {data:challengeId,error:insertError}=await admin.rpc("account_recovery_create_challenge",{p_profile_id:target.profile_id,p_phone_hash:phoneHash,p_otp:otp});
    if(insertError){const message=String(insertError.message??"");if(message.includes("RATE_LIMIT_MINUTE"))return json({error:"인증번호는 1분 뒤 다시 요청할 수 있습니다."},429);if(message.includes("RATE_LIMIT_HOUR"))return json({error:"인증 요청 횟수를 초과했습니다. 잠시 후 다시 시도해 주세요."},429);console.error("[account-recovery-otp] challenge create failed",insertError);return json({error:"인증 요청을 저장하지 못했습니다."},500);}
    if(target){
      const text=`[한살매 수업노트]\n계정 확인 인증번호: ${otp}\n5분 안에 입력해 주세요.`;
      const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone,from:sender,text,autoTypeDetect:true}})});
      if(!response.ok){console.error("[account-recovery-otp] solapi rejected",{status:response.status});return json({error:"인증 문자를 보내지 못했습니다. 잠시 후 다시 시도해 주세요."},502)}
    }
    return json({success:true,challengeId,expiresIn:300});
  }

  if(input.action==="verify"){
    const challengeId=input.challengeId??"",otp=digits(input.code??"");
    if(!challengeId||otp.length!==6)return json({error:"6자리 인증번호를 입력해 주세요."},400);
    const password=input.password??"";
    if(password.length<8)return json({error:"새 비밀번호는 8자 이상 입력해 주세요."},400);
    const {data:reset,error:resetError}=await admin.rpc("account_recovery_reset_password",{p_challenge_id:challengeId,p_otp:otp,p_password:password});
    if(resetError){console.error("[account-recovery-otp] password reset failed",resetError);return json({error:"새 비밀번호를 저장하지 못했습니다."},500)}
    if(!reset)return json({error:"인증번호가 만료되었거나 올바르지 않습니다."},400);
    return json({success:true});
  }
  return json({error:"지원하지 않는 요청입니다."},400);
});
