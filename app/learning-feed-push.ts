import type { SupabaseClient } from "@supabase/supabase-js";

type ClassCompletion={sourceType:"class_lesson";classId:string;date:string};
type CorrectionCompletion={sourceType:"correction";date:string;records:{assignmentId:string;startTime:string}[]};

export async function sendLearningFeedPush(supabase:SupabaseClient,completion:ClassCompletion|CorrectionCompletion){
  const{error}=await supabase.functions.invoke("send-learning-feed-push",{body:completion});
  if(error)console.error("[send-learning-feed-push] invocation failed",{sourceType:completion.sourceType,message:error.message});
}
