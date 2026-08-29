import type { SupabaseClient } from "@supabase/supabase-js";

type ClassCompletion={sourceType:"class_lesson";classId:string;date:string;studentIds:string[]};
type CorrectionCompletion={sourceType:"correction";date:string;studentIds:string[]};

export async function sendLearningFeedPush(supabase:SupabaseClient,completion:ClassCompletion|CorrectionCompletion){
  const body=completion.sourceType==="class_lesson"
    ? {kind:"class",sourceKey:`${completion.classId}:${completion.date}`,studentIds:completion.studentIds,date:completion.date}
    : {kind:"correction",sourceKey:completion.date,studentIds:completion.studentIds,date:completion.date};
  const{error}=await supabase.functions.invoke("send-learning-feed-push",{body});
  if(error)console.error("[send-learning-feed-push] invocation failed",{sourceType:completion.sourceType,message:error.message});
}
