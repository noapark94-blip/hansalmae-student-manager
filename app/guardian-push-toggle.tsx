"use client";

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type State="checking"|"unsupported"|"off"|"on"|"saving"|"error";
const VAPID_PUBLIC_KEY="BFtcz-HAAEgZVonjdQqk8hpZQwOMeQZObsTlL-jwoh_fdn9rWyt_GmaDOy77HEKQQ0qFazh-7PIGKtRB3BIfkuE";

function decodeKey(value:string){
  const normalized=value.replace(/-/g,"+").replace(/_/g,"/").padEnd(Math.ceil(value.length/4)*4,"=");
  return Uint8Array.from(atob(normalized),character=>character.charCodeAt(0));
}

export function GuardianPushToggle({supabase}:{supabase:SupabaseClient}){
  const supported=typeof window!=="undefined"&&"serviceWorker" in navigator&&"PushManager" in window&&"Notification" in window;
  const[state,setState]=useState<State>(supported?"checking":"unsupported");
  const[guardian,setGuardian]=useState(false);
  const[showGuide,setShowGuide]=useState(false);
  useEffect(()=>{
    if(!supported)return;
    let active=true;
    void supabase.auth.getUser().then(async({data})=>{
      const user=data.user;
      if(!active||!user)return;
      const{data:profile}=await supabase.from("profiles").select("role").eq("id",user.id).maybeSingle();
      if(!active||profile?.role!=="guardian")return;
      setGuardian(true);
      if(user.user_metadata?.guardian_push_guide_seen!==true){
        setShowGuide(true);
        await supabase.auth.updateUser({data:{guardian_push_guide_seen:true}});
      }
      const registration=await navigator.serviceWorker.register("/push-service-worker.js");
      const subscription=await registration.pushManager.getSubscription();
      if(active)setState(subscription?"on":"off");
    }).catch(()=>{if(active)setState("error")});
    return()=>{active=false};
  },[supported,supabase]);
  async function toggle(){
    if(state!=="on"&&state!=="off")return;
    setState("saving");
    try{
      const registration=await navigator.serviceWorker.ready;
      const existing=await registration.pushManager.getSubscription();
      if(existing){
        const{error}=await supabase.from("push_subscriptions").delete().eq("endpoint",existing.endpoint);
        if(error)throw error;
        await existing.unsubscribe();setState("off");return;
      }
      const permission=await Notification.requestPermission();
      if(permission!=="granted"){setState("off");return}
      const subscription=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:decodeKey(VAPID_PUBLIC_KEY)});
      const json=subscription.toJSON();
      const{data:{user}}=await supabase.auth.getUser();
      if(!user||!json.keys?.p256dh||!json.keys.auth)throw new Error("구독 정보를 확인할 수 없습니다.");
      const{error}=await supabase.from("push_subscriptions").upsert({user_id:user.id,endpoint:subscription.endpoint,p256dh:json.keys.p256dh,auth:json.keys.auth,user_agent:navigator.userAgent},{onConflict:"endpoint"});
      if(error){await subscription.unsubscribe();throw error}
      setState("on");
    }catch{setState("error")}
  }
  if(!guardian||state==="unsupported"||state==="checking")return null;
  return <div className="guardian-push-setting">{showGuide?<p><b>기기 알림을 켜 보세요</b><span>수업·첨삭 리포트가 처음 완료되면 이 기기에서 바로 알려드려요.</span></p>:null}<button type="button" className={`guardian-push-toggle ${state}`} onClick={()=>void toggle()} disabled={state==="saving"} aria-pressed={state==="on"}>
    <span aria-hidden="true">{state==="on"?"●":"○"}</span>{state==="saving"?"설정 중…":state==="on"?"기기 알림 켜짐":state==="error"?"기기 알림 다시 시도":"이 기기에서 알림 받기"}
  </button></div>;
}
