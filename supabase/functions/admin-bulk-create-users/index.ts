import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
type Role="admin"|"teacher"|"student"|"guardian";
type Row={email?:string;password?:string;displayName?:string;phone?:string|null;role?:Role;studentId?:string|null;childIds?:string[];classIds?:string[]};

Deno.serve(async(request)=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),authorization=request.headers.get("Authorization");
  if(!url||!anon||!service)return json({error:"서버 계정 생성 설정이 없습니다."},500);
  if(!authorization?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  const authClient=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
  const adminClient=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const{data:userData,error:userError}=await authClient.auth.getUser(authorization.slice(7));
  if(userError||!userData.user)return json({error:"로그인 정보를 확인할 수 없습니다."},401);
  const{data:actorRole,error:roleError}=await authClient.rpc("current_user_role");
  if(roleError||actorRole!=="admin")return json({error:"관리자만 로그인 계정을 일괄 생성할 수 있습니다."},403);
  let body:{rows?:Row[];fileName?:string};try{body=await request.json()}catch{return json({error:"입력 내용을 확인해 주세요."},400)}
  const rows=body.rows??[];if(rows.length<1||rows.length>50)return json({error:"한 번에 1~50개 계정까지 생성할 수 있습니다."},400);
  const emails=new Set<string>();
  for(let i=0;i<rows.length;i++){const r=rows[i],email=r.email?.trim().toLowerCase();if(!email||!/^\S+@\S+\.\S+$/.test(email))return json({error:`${i+2}행의 이메일을 확인해 주세요.`},400);if(emails.has(email))return json({error:`${i+2}행의 이메일이 CSV 안에서 중복됩니다.`},400);emails.add(email);if(!r.password||r.password.length<8)return json({error:`${i+2}행의 임시 비밀번호를 확인해 주세요.`},400);if(!r.displayName?.trim())return json({error:`${i+2}행의 표시 이름을 확인해 주세요.`},400);if(!r.role||!["admin","teacher","student","guardian"].includes(r.role))return json({error:`${i+2}행의 역할을 확인해 주세요.`},400);if(r.role==="guardian"&&!r.phone?.trim())return json({error:`${i+2}행의 학부모 연락처를 입력해 주세요.`},400)}
  const createdIds:string[]=[];const credentials:{email:string;password:string;displayName:string;role:Role}[]=[];
  try{
    for(const row of rows){const email=row.email!.trim().toLowerCase(),displayName=row.displayName!.trim();const{data:created,error:createError}=await adminClient.auth.admin.createUser({email,password:row.password!,email_confirm:true,user_metadata:{display_name:displayName,role:row.role}});if(createError||!created.user)throw new Error(`${email}: ${createError?.message??"계정을 만들지 못했습니다."}`);createdIds.push(created.user.id);const{error:settingsError}=await authClient.rpc("admin_save_account_settings",{p_profile_id:created.user.id,p_display_name:displayName,p_phone:row.phone?.trim()||null,p_role:row.role,p_is_active:true,p_student_id:row.role==="student"?row.studentId||null:null,p_child_ids:row.role==="guardian"?row.childIds??[]:[]});if(settingsError)throw new Error(`${email}: ${settingsError.message}`);if(row.role==="teacher"){const{error:classError}=await authClient.rpc("admin_set_teacher_classes",{p_profile_id:created.user.id,p_class_ids:row.classIds??[]});if(classError)throw new Error(`${email}: ${classError.message}`)}credentials.push({email,password:row.password!,displayName,role:row.role!})}
    const{error:logError}=await authClient.rpc("admin_log_bulk_account_import",{p_file_name:body.fileName??null,p_account_count:rows.length});if(logError)throw new Error(logError.message);
    return json({created:credentials});
  }catch(error){
    if(createdIds.length){
      const{data:guardianRows}=await adminClient.from("guardians").select("id").in("profile_id",createdIds);
      const guardianIds=(guardianRows??[]).map(row=>row.id);
      if(guardianIds.length)await adminClient.from("student_guardians").delete().in("guardian_id",guardianIds);
      await adminClient.from("guardians").delete().in("profile_id",createdIds);
      await adminClient.from("teachers").delete().in("profile_id",createdIds);
      for(const id of createdIds.reverse())await adminClient.auth.admin.deleteUser(id);
    }
    return json({error:error instanceof Error?error.message:"계정 일괄 생성에 실패했습니다."},400);
  }
});
