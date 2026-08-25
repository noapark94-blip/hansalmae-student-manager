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
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),pepper=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey=credential(Deno.env.get("SOLAPI_API_KEY")),apiSecret=credential(Deno.env.get("SOLAPI_API_SECRET")),sender=digits(Deno.env.get("SOLAPI_SENDER_NUMBER")??"");
  if(!url||!service||!pepper||!apiKey||!apiSecret||!sender)return json({error:"문자 인증 서버 설정을 확인해 주세요."},500);
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const matchingProfiles=async(name:string,phone:string)=>{
    const{data:profiles,error:profilesError}=await admin.from("profiles").select("id,display_name,phone,is_active").eq("is_active",true).ilike("display_name",name);
    if(profilesError)throw profilesError;
    const matches:{id:string;display_name:string|null;phone:string|null;is_active:boolean}[]=[];
    for(const profile of profiles??[]){
      if(digits(profile.phone??"")===phone){matches.push(profile);continue}
      const[{data:students,error:studentError},{data:guardians,error:guardianError}]=await Promise.all([
        admin.from("students").select("phone").eq("profile_id",profile.id),
        admin.from("guardians").select("phone").eq("profile_id",profile.id)
      ]);
      if(studentError)console.warn("[account-recovery-otp] student phone lookup skipped",{profileId:profile.id,code:studentError.code});
      if(guardianError)console.warn("[account-recovery-otp] guardian phone lookup skipped",{profileId:profile.id,code:guardianError.code});
      const registeredPhones=[...(students??[]).map(row=>row.phone),...(guardians??[]).map(row=>row.phone)].map(value=>digits(value??"")).filter(Boolean);
      if(registeredPhones.includes(phone))matches.push(profile);
    }
    return matches;
  };
  let input:{action?:string;purpose?:"id"|"password";name?:string;phone?:string;challengeId?:string;code?:string;password?:string;accountType?:"student"|"guardian"|"staff";registeredPhone?:string;reachablePhone?:string;reason?:"phone_changed"|"sms_unavailable"|"other"};
  try{input=await request.json()}catch{return json({error:"요청 정보를 확인해 주세요."},400)}

  if(input.action==="lookup-id"){
    const name=(input.name??"").trim(),phone=digits(input.phone??"");if(!name||phone.length<10)return json({error:"이름과 연락처를 정확히 입력해 주세요."},400);
    let matches:{id:string}[];try{matches=await matchingProfiles(name,phone)}catch(error){console.error("[account-recovery-otp] lookup failed",error);return json({error:"계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."},500)}
    if(matches.length!==1)return json({error:"입력한 정보와 일치하는 계정을 찾지 못했습니다."},404);const{data:userData}=await admin.auth.admin.getUserById(matches[0].id);if(!userData.user?.email)return json({error:"로그인 아이디를 확인하지 못했습니다."},500);return json({success:true,loginId:userData.user.email});
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
    const phoneHash=await hash(`${phone}:${pepper}`),now=Date.now();
    const {data:recent}=await admin.from("account_recovery_challenges").select("created_at").eq("phone_hash",phoneHash).eq("purpose","password").gte("created_at",new Date(now-60*60*1000).toISOString()).order("created_at",{ascending:false});
    if(recent?.[0]&&now-new Date(recent[0].created_at).getTime()<60_000)return json({error:"인증번호는 1분 뒤 다시 요청할 수 있습니다."},429);
    if((recent?.length??0)>=5)return json({error:"인증 요청 횟수를 초과했습니다. 잠시 후 다시 시도해 주세요."},429);
    let matches:{id:string}[];try{matches=await matchingProfiles(name,phone)}catch(error){console.error("[account-recovery-otp] recovery lookup failed",error);return json({error:"계정 정보를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요."},500)}
    const target=matches.length===1?matches[0]:null,otp=code(),challengeId=crypto.randomUUID();
    const {error:insertError}=await admin.from("account_recovery_challenges").insert({id:challengeId,profile_id:target?.id??null,purpose,phone_hash:phoneHash,code_hash:await hash(`${challengeId}:${otp}:${pepper}`),expires_at:new Date(now+5*60*1000).toISOString()});
    if(insertError)return json({error:"인증 요청을 저장하지 못했습니다."},500);
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
    const {data:challenge}=await admin.from("account_recovery_challenges").select("*").eq("id",challengeId).maybeSingle();
    if(!challenge||challenge.consumed_at||new Date(challenge.expires_at).getTime()<Date.now()||challenge.attempts>=5)return json({error:"인증번호가 만료되었거나 올바르지 않습니다."},400);
    const valid=challenge.code_hash===await hash(`${challengeId}:${otp}:${pepper}`);
    if(!valid){await admin.from("account_recovery_challenges").update({attempts:challenge.attempts+1}).eq("id",challengeId);return json({error:"인증번호가 만료되었거나 올바르지 않습니다."},400)}
    if(!challenge.profile_id)return json({error:"인증번호가 만료되었거나 올바르지 않습니다."},400);
    if(challenge.purpose==="id"){
      const {data:userData,error:userError}=await admin.auth.admin.getUserById(challenge.profile_id);
      if(userError||!userData.user?.email)return json({error:"로그인 아이디를 확인하지 못했습니다."},500);
      await admin.from("account_recovery_challenges").update({consumed_at:new Date().toISOString()}).eq("id",challengeId).is("consumed_at",null);
      return json({success:true,loginId:userData.user.email});
    }
    const password=input.password??"";
    if(password.length<8)return json({error:"새 비밀번호는 8자 이상 입력해 주세요."},400);
    const {error:updateError}=await admin.auth.admin.updateUserById(challenge.profile_id,{password});
    if(updateError)return json({error:"새 비밀번호를 저장하지 못했습니다."},500);
    await Promise.all([admin.from("profiles").update({must_change_password:false}).eq("id",challenge.profile_id),admin.from("account_recovery_challenges").update({consumed_at:new Date().toISOString()}).eq("id",challengeId).is("consumed_at",null)]);
    return json({success:true});
  }
  return json({error:"지원하지 않는 요청입니다."},400);
});
