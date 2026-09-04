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
  let input:{studentId?:string;reportType?:ReportType;periodStart?:string;periodEnd?:string;lessonSummary?:string;attendanceSummary?:string;examSummary?:string;homeworkSummary?:string;learningSummary?:string;resendDeliveryId?:string};
  try{input=await request.json()}catch{return json({error:"발송 내용을 확인해 주세요."},400)}
  const authClient=createClient(url,anon,{global:{headers:{Authorization:bearer}},auth:{persistSession:false}}),admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const resend=Boolean(input.resendDeliveryId);
  const{data,error}=resend
    ?await authClient.rpc("staff_prepare_learning_alimtalk_resend",{p_delivery_id:input.resendDeliveryId})
    :await authClient.rpc("staff_claim_learning_alimtalk",{p_student_id:input.studentId,p_report_type:input.reportType,p_period_start:input.periodStart,p_period_end:input.periodEnd,p_lesson_summary:input.lessonSummary,p_attendance_summary:input.attendanceSummary,p_learning_summary:input.learningSummary});
  if(error)return json({error:error.message},error.message.includes("관리자")?403:400);
  const claimed=(data??[]) as{id?:string;delivery_id?:string;recipient_phone:string;guardian_name:string;student_name:string;report_type?:ReportType;template_variables:Record<string,string>}[];
  if(!claimed.length)return json({error:"발송할 학부모 연락처를 찾지 못했습니다."},400);
  const resultRow=claimed[0],variables=resultRow.template_variables,deliveryId=String(resultRow.id??resultRow.delivery_id),reportType=resultRow.report_type??input.reportType;
  if(!reportType)return json({error:"발송 유형을 확인할 수 없습니다."},400);
  const templateId=clean(Deno.env.get(reportType==="weekly"?"SOLAPI_ALIMTALK_WEEKLY_TEMPLATE_ID":"SOLAPI_ALIMTALK_DAILY_TEMPLATE_ID"));
  if(!apiKey||!apiSecret||!sender||!pfId||!templateId)return json({error:"솔라피 알림톡 채널 또는 승인 템플릿이 아직 설정되지 않았습니다."},503);
  const{data:userData}=await authClient.auth.getUser();
  if(!userData.user)return json({error:"로그인 정보를 확인할 수 없습니다."},401);
  const start=String(variables.periodStart),end=String(variables.periodEnd),period=reportType==="daily"?formatDate(start):`${formatDate(start)}~${formatDate(end)}`;
  const learningDetails=String(variables.learningSummary??"").trim()||"수업 기록 완료";
  const kakaoVariables={"#{학생명}":variables.studentName,[reportType==="weekly"?"#{기간}":"#{기록일}"]:period,"#{수업요약}":variables.lessonSummary,"#{출결요약}":variables.attendanceSummary,"#{학습상세요약}":learningDetails};
  const details=[`■ 수업\n${variables.lessonSummary}`,`■ 출결\n${variables.attendanceSummary}`,`■ 학습 상세\n${learningDetails}`].join("\n\n");
  const fallback=`[한살매 수업노트]\n\n${variables.studentName} 학생의 ${period} ${reportType==="weekly"?"주간 학습요약":"학습기록"}입니다.\n\n${details}\n\n자세한 수업 내용과 선생님 피드백은\n아래 '학습기록 확인' 버튼에서 확인해 주세요.`;
  const finish=async(status:"sent"|"failed",messageId:string|null,groupId:string|null,reason:string|null)=>resend
    ?admin.rpc("internal_log_learning_alimtalk_resend",{p_delivery_id:deliveryId,p_status:status,p_provider_message_id:messageId,p_provider_group_id:groupId,p_error_message:reason,p_created_by:userData.user.id})
    :admin.rpc("internal_finish_learning_alimtalk",{p_delivery_id:deliveryId,p_status:status,p_provider_message_id:messageId,p_provider_group_id:groupId,p_error_message:reason});
  try{
    const response=await fetch("https://api.solapi.com/messages/v4/send",{method:"POST",headers:{Authorization:await authorization(apiKey,apiSecret),"Content-Type":"application/json"},body:JSON.stringify({message:{to:phone(resultRow.recipient_phone),from:sender,text:fallback,autoTypeDetect:true,kakaoOptions:{pfId,templateId,variables:kakaoVariables}}})});
    const result=await response.json().catch(()=>({})) as{messageId?:string;groupId?:string;errorCode?:string;errorMessage?:string;message?:string};
    if(!response.ok){const reason=safe(result.errorMessage??result.message??`SOLAPI ${response.status}`);await finish("failed",null,null,reason);return json({error:`솔라피 알림톡 요청 실패${result.errorCode?` (${result.errorCode})`:""}: ${reason}`},502)}
    await finish("sent",result.messageId??null,result.groupId??null,null);
    return json({sent:1,deliveryId});
  }catch(error){const reason=safe(error instanceof Error?error.message:error);await finish("failed",null,null,reason);return json({error:reason},502)}
});

function formatDate(value:string){const parts=value.split("-");return `${Number(parts[1])}월 ${Number(parts[2])}일`}
type ReportType="daily"|"weekly";
