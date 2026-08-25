import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
const clean=(value:unknown)=>String(value??"").trim();

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!service)return json({error:"회원가입 서버 설정이 없습니다."},500);
  let input:{email?:string;password?:string;guardianName?:string;guardianPhone?:string;studentName?:string;school?:string;grade?:string};
  try{input=await request.json()}catch{return json({error:"입력 내용을 확인해 주세요."},400)}
  const email=clean(input.email).toLowerCase(),password=String(input.password??""),guardianName=clean(input.guardianName),guardianPhone=clean(input.guardianPhone),studentName=clean(input.studentName),school=clean(input.school),grade=clean(input.grade);
  if(!email||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return json({error:"올바른 이메일을 입력해 주세요."},400);
  if(password.length<8)return json({error:"비밀번호는 8자 이상 입력해 주세요."},400);
  if(!guardianName||!guardianPhone||!studentName)return json({error:"학부모 이름·연락처·자녀 이름을 모두 입력해 주세요."},400);
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:created,error:createError}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{display_name:guardianName}});
  if(createError||!created.user)return json({error:createError?.message?.includes("already")?"이미 가입된 이메일입니다.":"계정을 만들지 못했습니다."},400);
  const profile={id:created.user.id,role:"guardian",display_name:guardianName,phone:guardianPhone,is_active:false};
  const {error:profileError}=await admin.from("profiles").upsert(profile,{onConflict:"id"});
  if(profileError){await admin.auth.admin.deleteUser(created.user.id);return json({error:"가입 요청 계정을 준비하지 못했습니다."},500)}
  const {error:requestError}=await admin.from("guardian_link_requests").insert({profile_id:created.user.id,guardian_name:guardianName,guardian_phone:guardianPhone,student_name:studentName,school:school||null,grade:grade||null});
  if(requestError){await admin.auth.admin.deleteUser(created.user.id);return json({error:"자녀 연결 요청을 등록하지 못했습니다."},500)}
  return json({success:true});
});
