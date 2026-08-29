import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Content-Type":"application/json"};
const PUBLIC_KEY="BFtcz-HAAEgZVonjdQqk8hpZQwOMeQZObsTlL-jwoh_fdn9rWyt_GmaDOy77HEKQQ0qFazh-7PIGKtRB3BIfkuE";
type Body={kind:"class"|"correction"|"reply";sourceKey:string;studentIds:string[];date:string;title?:string;body?:string;url?:string;recipientProfileId?:string};

Deno.serve(async req=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin=createClient(url,service),body=await req.json() as Body;
    const internalKey=req.headers.get("x-push-dispatch-key");
    const{data:expectedInternalKey}=internalKey?await admin.rpc("push_dispatch_webhook_key"):{data:null};
    const internal=Boolean(internalKey&&expectedInternalKey&&internalKey===expectedInternalKey);
    if(!internal){
      const authorization=req.headers.get("Authorization")||"";
      const caller=createClient(url,anon,{global:{headers:{Authorization:authorization}}});
      const{data:{user}}=await caller.auth.getUser();
      if(!user)throw new Error("로그인이 필요합니다.");
      const{data:profile}=await admin.from("profiles").select("role").eq("id",user.id).single();
      if(!["admin","teacher","assistant","manager"].includes(profile?.role))throw new Error("발송 권한이 없습니다.");
    }
    const studentIds=[...new Set(body.studentIds||[])].slice(0,100);
    if(!body.sourceKey||!studentIds.length)throw new Error("발송 대상이 없습니다.");
    const{data:students}=await admin.from("students").select("id,name").in("id",studentIds);
    const recipients=new Map<string,string[]>();
    if(internal&&body.recipientProfileId){recipients.set(body.recipientProfileId,studentIds)}
    else{
      const{data:links}=await admin.from("student_guardians").select("student_id,guardians!inner(profile_id)").in("student_id",studentIds);
      for(const link of links||[]){const guardian=link.guardians as unknown as{profile_id:string};if(guardian?.profile_id)recipients.set(guardian.profile_id,[...(recipients.get(guardian.profile_id)||[]),link.student_id])}
    }
    const{data:secret}=await admin.rpc("push_vapid_private_key");
    if(!secret)throw new Error("푸시 발송 키가 설정되지 않았습니다.");
    webpush.setVapidDetails("mailto:noapark94@gmail.com",PUBLIC_KEY,secret);
    let sent=0,attempted=0,skipped=0;
    for(const[profileId,ids]of recipients){
      const key=`${body.kind}:${body.sourceKey}`;
      const{error:dedupe}=await admin.from("push_delivery_log").insert({notification_key:key,profile_id:profileId});
      if(dedupe){
        if(dedupe.code==="23505"){skipped++;continue}
        console.error("[web-push] delivery log insert failed",{profileId,key,code:dedupe.code,message:dedupe.message});
        throw new Error(`푸시 발송 기록 생성 실패: ${dedupe.message}`);
      }
      const names=(students||[]).filter(student=>ids.includes(student.id)).map(student=>student.name).join("·");
      const{data:subscriptions}=await admin.from("push_subscriptions").select("id,endpoint,p256dh,auth").eq("profile_id",profileId);
      console.log("[web-push] recipient resolved",{profileId,key,subscriptions:subscriptions?.length||0});
      let recipientSent=0;
      for(const subscription of subscriptions||[]){
        attempted++;
        try{
          await webpush.sendNotification({endpoint:subscription.endpoint,keys:{p256dh:subscription.p256dh,auth:subscription.auth}},JSON.stringify({title:body.title||"새 학습 피드가 도착했어요",body:body.body||`${names||"자녀"} 학생의 ${body.date.slice(5).replace("-",".")} ${body.kind==="correction"?"첨삭":body.kind==="reply"?"댓글":"수업"} 기록이 등록되었습니다.`,url:body.url||"/",tag:key}));
          sent++;recipientSent++;
        }catch(error){
          const status=(error as{statusCode?:number}).statusCode;
          console.error("[web-push] delivery failed",{subscriptionId:subscription.id,status,message:error instanceof Error?error.message:String(error),body:(error as{body?:string}).body});
          if(status===404||status===410)await admin.from("push_subscriptions").delete().eq("id",subscription.id);
        }
      }
      if(recipientSent===0)await admin.from("push_delivery_log").delete().eq("notification_key",key).eq("profile_id",profileId);
    }
    const status=recipients.size>0&&sent===0&&skipped===0?502:200;
    return new Response(JSON.stringify({sent,attempted,skipped,recipients:recipients.size}),{status,headers:cors});
  }catch(error){return new Response(JSON.stringify({error:error instanceof Error?error.message:"발송 실패"}),{status:400,headers:cors})}
});
