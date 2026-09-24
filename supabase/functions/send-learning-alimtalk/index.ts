import { createClient } from "npm:@supabase/supabase-js@2";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const json=(body:Record<string,unknown>,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const clean=(value:string|undefined)=>(value??"").trim().replace(/^(?:"|')|(?:"|')$/g,"").replace(/[\s\uFEFF]+/g,"");
const phone=(value:string)=>value.replace(/\D/g,"");
const safe=(value:unknown)=>String(value??"알림톡 발송 중 오류가 발생했습니다.").replace(/apiKey\s*=\s*[^,\s"']+/gi,"apiKey=[숨김]").replace(/signature\s*=\s*[^,\s"']+/gi,"signature=[숨김]").slice(0,500);

async function authorization(apiKey:string,apiSecret:string){
  const date=new Date().toISOString(),salt=crypto.randomUUID().replaceAll("-","");
  const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(apiSecret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  const bytes=await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(date+salt));
  const signature=Array.from(new Uint8Array(bytes),byte=>byte.toString(16).padStart(2,"0")).join("");
  return `HMAC-SHA256 apiKey=${apiKey}, date=${date}, salt=${salt}, signature=${signature}`;
}

Deno.serve(async request=>{
  if(request.method==="OPTIONS")return new Response("ok",{headers:cors});
  if(request.method!=="POST")return json({error:"지원하지 않는 요청입니다."},405);
  const url=Deno.env.get("SUPABASE_URL"),anon=Deno.env.get("SUPABASE_ANON_KEY"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),bearer=request.headers.get("Authorization");
  const apiKey=clean(Deno.env.get("SOLAPI_API_KEY")),apiSecret=clean(Deno.env.get("SOLAPI_API_SECRET")),sender=phone(Deno.env.get("SOLAPI_SENDER_NUMBER")??""),pfId=clean(Deno.env.get("SOLAPI_KAKAO_PF_ID"));
  if(!url||!anon||!service)return json({error:"알림톡 서버 연결 설정이 없습니다."},500);
  if(!bearer?.startsWith("Bearer "))return json({error:"로그인이 필요합니다."},401);
  let input:{studentId?:string;sourceVersion?:string;reportType?:ReportType;periodStart?:string;periodEnd?:string;lessonSummary?:string;attendanceSummary?:string;examSummary?:string;homeworkSummary?:string;learningSummary?:string;resendDeliveryId?:string};
  try{input=await request.json()}catch{return json({error:"발송 내용을 확인해 주세요."},400)}
  const authClient=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false}}),admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  if(!input||typeof input!=="object")return json({error:"발송 내용을 확인해 주세요."},400);
  const resend=Boolean(input.resendDeliveryId);
  if(!resend&&input.reportType!=="daily"&&input.reportType!=="weekly")return json({error:"발송 유형을 확인해 주세요."},400);
  const configuredTemplate=(kind:string)=>clean(Deno.env.get(kind==="weekly"?"SOLAPI_ALIMTALK_WEEKLY_TEMPLATE_ID":"SOLAPI_ALIMTALK_DAILY_TEMPLATE_ID"));
  if(!apiKey||!apiSecret||!sender||!pfId||(!resend&&!configuredTemplate(input.reportType!)))return json({error:"솔라피 알림톡 채널 또는 승인 템플릿이 아직 설정되지 않았습니다."},503);
  let userId:string,providerAuthorization:string;
  try{
    const{data:userData,error:userError}=await authClient.auth.getUser();
    if(userError||!userData.user)return json({error:"로그인 정보를 확인할 수 없습니다."},401);
    userId=userData.user.id;
    providerAuthorization=await authorization(apiKey,apiSecret);
  }catch{return json({error:"로그인 또는 발송 준비를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요."},503)}
  const{data,error}=resend
    ?await authClient.rpc("staff_prepare_learning_alimtalk_resend",{p_delivery_id:input.resendDeliveryId})
    :await authClient.rpc("staff_claim_learning_alimtalk_current",{p_source_version:input.sourceVersion??null,p_student_id:input.studentId,p_report_type:input.reportType,p_period_start:input.periodStart,p_period_end:input.periodEnd,p_lesson_summary:input.lessonSummary,p_attendance_summary:input.attendanceSummary,p_learning_summary:input.learningSummary});
  if(error)return json({error:error.message},error.message.includes("관리자")?403:400);
  const claimed=(data??[]) as{id?:string;delivery_id?:string;recipient_phone:string;guardian_name:string;student_name:string;report_type?:ReportType;template_variables:Record<string,string>}[];
  if(!claimed.length)return json({error:"발송할 학부모 연락처를 찾지 못했습니다."},400);
  const resultRow=claimed[0],variables=resultRow.template_variables,deliveryId=String(resultRow.id??resultRow.delivery_id),reportType=resultRow.report_type??input.reportType;
  if(!reportType)return json({error:"발송 유형을 확인할 수 없습니다."},400);
  const templateId=configuredTemplate(reportType);
  // Resend preparation is read-only; a missing template cannot strand a delivery.
  if(!templateId)return json({error:"승인된 알림톡 템플릿이 설정되지 않았습니다."},503);
  const start=String(variables.periodStart),end=String(variables.periodEnd),period=reportType==="daily"?formatDate(start):`${formatDate(start)}~${formatDate(end)}`;
  const learningDetails=String(variables.learningSummary??"").trim()||"등록된 학습 상세가 없습니다.";
  const kakaoVariables={"#{학생명}":variables.studentName,[reportType==="weekly"?"#{기간}":"#{기록일}"]:period,"#{수업요약}":variables.lessonSummary,"#{출결요약}":variables.attendanceSummary,"#{학습상세요약}":learningDetails};
  const details=[`■ 수업\n${variables.lessonSummary}`,`■ 출결\n${variables.attendanceSummary}`,`■ 학습 상세\n${learningDetails}`].join("\n\n");
  const fallback=`[한살매 수업노트]\n\n${variables.studentName} 학생의 ${period} ${reportType==="weekly"?"주간 학습요약":"학습기록"}입니다.\n\n${details}\n\n자세한 수업 내용과 선생님 피드백은\n아래 '학습기록 확인' 버튼에서 확인해 주세요.`;
  const resendAttemptId=crypto.randomUUID();
  const finish=async(status:"sent"|"failed",messageId:string|null,groupId:string|null,reason:string|null)=>{
    // Retry persistence only. A stable attempt ID prevents duplicate resend logs.
    const attempt={id:resendAttemptId,delivery_id:deliveryId,status,provider_message_id:messageId,provider_group_id:groupId,error_message:reason,created_by:userId,sent_at:status==="sent"?new Date().toISOString():null};
    for(let retry=0;retry<3;retry++){
      try{
        if(resend){
          const{data,error}=await admin.from("learning_alimtalk_resend_attempts").upsert(attempt,{onConflict:"id"}).select("id").single();
          if(!error&&data?.id===resendAttemptId)return true;
        }else{
          const{data,error}=await admin.rpc("internal_finish_learning_alimtalk",{p_delivery_id:deliveryId,p_status:status,p_provider_message_id:messageId,p_provider_group_id:groupId,p_error_message:reason});
          if(!error&&data===true)return true;
          // A previous write may have committed even if its response was lost.
          const saved=await admin.from("learning_alimtalk_deliveries").select("status,provider_message_id,provider_group_id,error_message").eq("id",deliveryId).single();
          if(!saved.error&&saved.data?.status===status&&saved.data.provider_message_id===messageId&&saved.data.provider_group_id===groupId&&(status==="sent"||saved.data.error_message===reason))return true;
        }
      }catch{/* Retry the same persistence operation, never the provider request. */}
    }
    return false;
  };
  const persistenceError=(accepted:boolean)=>json({error:accepted?"알림톡 발송은 접수됐지만 이력 저장을 완료하지 못했습니다. 중복 발송을 피하려면 다시 보내지 말고 관리자에게 확인해 주세요.":"발송 처리 결과를 저장하지 못했습니다. 다시 보내기 전에 관리자에게 발송 상태를 확인해 주세요.",code:"DELIVERY_PERSISTENCE_FAILED",providerAccepted:accepted,deliveryId},503);
  const messageLength=Array.from(fallback).length;
  if(messageLength>1000){
    const reason=`알림톡 전체 내용이 ${messageLength}자로 발송 한도 1,000자를 ${messageLength-1000}자 초과했습니다. 수업·시험·숙제 요약을 줄여 주세요.`;
    if(!await finish("failed",null,null,reason))return persistenceError(false);
    return json({error:reason,messageLength,maxLength:1000},400);
  }
  let response:Response;
  try{
    response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:providerAuthorization,"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone(resultRow.recipient_phone),from:sender,text:fallback,autoTypeDetect:true,kakaoOptions:{pfId,templateId,variables:kakaoVariables}}})});
  }catch{
    // A timeout does not prove that the provider rejected the request.
    // Keep the claim blocked instead of marking it retryable and sending twice.
    return json({error:"발송 서버의 응답을 확인하지 못했습니다. 이미 접수됐을 수 있으니 다시 보내지 말고 관리자에게 발송 여부를 확인해 주세요.",code:"DELIVERY_OUTCOME_UNKNOWN",deliveryId},503);
  }
  const result=await response.json().catch(()=>({})) as{messageId?:string;groupId?:string;errorCode?:string;errorMessage?:string;message?:string};
  if(!response.ok){
    if(response.status>=500||response.status===408)return json({error:"발송 서버 오류로 접수 여부를 확인하지 못했습니다. 다시 보내기 전에 관리자에게 확인해 주세요.",code:"DELIVERY_OUTCOME_UNKNOWN",deliveryId},503);
    const reason=safe(result.errorMessage??result.message??`SOLAPI ${response.status}`);
    if(!await finish("failed",null,null,reason))return persistenceError(false);
    return json({error:`솔라피 알림톡 요청 실패${result.errorCode?` (${result.errorCode})`:""}: ${reason}`},502);
  }
  if(!result.messageId)return json({error:"발송 응답에 확인 번호가 없습니다. 중복 발송을 피하려면 관리자에게 접수 여부를 확인해 주세요.",code:"DELIVERY_OUTCOME_UNKNOWN",deliveryId},503);
  if(!await finish("sent",result.messageId,result.groupId??null,null))return persistenceError(true);
  return json({sent:1,deliveryId});
});

function formatDate(value:string){const parts=value.split("-");return `${Number(parts[1])}월 ${Number(parts[2])}일`}
type ReportType="daily"|"weekly";
