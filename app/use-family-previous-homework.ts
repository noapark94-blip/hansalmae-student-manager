"use client";
import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

export function useFamilyPreviousHomework(supabase: SupabaseClient,studentId:string,recordId:string,kind:"lesson"|"correction") {
  const key=JSON.stringify([studentId,recordId,kind]);
  const [attempt,setAttempt]=useState(0);
  const [state,setState]=useState({key:"",value:"",error:"",loading:true});
  useEffect(()=>{
    let active=true;
    setState({key,value:"",error:"",loading:true});
    void Promise.resolve().then(async()=>{
      const result=await supabase.rpc("family_previous_homework",{p_student_id:studentId,p_record_id:recordId,p_kind:kind});
      if(!active)return;
      if(result.error||typeof result.data!=="string")throw new Error("조회 실패");
      setState({key,value:result.data,error:"",loading:false});
    }).catch(()=>{if(active)setState({key,value:"",error:"지난 숙제를 불러오지 못했습니다.",loading:false});});
    return()=>{active=false};
  },[supabase,studentId,recordId,kind,key,attempt]);
  return {...(state.key===key?state:{key,value:"",error:"",loading:true}),retry:()=>setAttempt(value=>value+1)};
}
