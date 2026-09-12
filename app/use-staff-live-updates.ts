"use client";
import {useCallback,useEffect,useLayoutEffect,useRef} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {createCorrectionRefreshQueue,type RefreshBatch} from "./correction-live-refresh";

export function useStaffLiveUpdates(supabase:SupabaseClient,scope:string,filter:string,
  read:(batch:RefreshBatch,active:()=>boolean)=>Promise<void>,onError:(error:unknown)=>void,initial=false) {
  const latest=useRef({read,onError});
  useLayoutEffect(()=>{latest.current={read,onError};});
  const queueRef=useRef<ReturnType<typeof createCorrectionRefreshQueue>|null>(null);
  const refresh=useCallback(async()=>{queueRef.current?.request({full:true});},[]);
  useEffect(()=>{
    let active=true;
    const queue=createCorrectionRefreshQueue(batch=>latest.current.read(batch,()=>active),error=>latest.current.onError(error),{visible:()=>document.visibilityState!=="hidden"});
    queueRef.current=queue;
    if(initial)queue.request({full:true},true);
    const channel=supabase.channel(`staff-live-${scope}`)
      .on("postgres_changes",{event:"*",schema:"public",table:"staff_live_signals",filter},payload=>{
        const row=payload.new as {entity_id?:string};
        if(row.entity_id)queue.request({id:row.entity_id});
      }).subscribe(status=>{
        if(status==="SUBSCRIBED")queue.request({full:true});
        else if(active&&(status==="CHANNEL_ERROR"||status==="TIMED_OUT"))latest.current.onError(new Error("자동 반영 연결이 끊겼습니다. 화면으로 돌아오면 최신 내용을 다시 확인합니다."));
      });
    const resume=()=>{if(document.visibilityState!=="hidden")queue.request({full:true});};
    window.addEventListener("focus",resume);window.addEventListener("online",resume);
    document.addEventListener("visibilitychange",resume);
    return()=>{active=false;queue.dispose();if(queueRef.current===queue)queueRef.current=null;void supabase.removeChannel(channel);
      window.removeEventListener("focus",resume);window.removeEventListener("online",resume);document.removeEventListener("visibilitychange",resume);};
  },[supabase,scope,filter,initial]);
  return refresh;
}
