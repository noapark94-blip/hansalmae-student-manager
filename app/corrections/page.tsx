"use client";

import { useEffect, useMemo, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { createSupabaseBrowserClient } from "../supabase";
import { CorrectionManagementBoard } from "../correction-management-board";

export default function CorrectionsPage(){
  const supabase=useMemo(()=>createSupabaseBrowserClient(),[]);
  const[user,setUser]=useState<User|null>(null);
  const[ready,setReady]=useState(!supabase);
  const[allowed,setAllowed]=useState(false);
  useEffect(()=>{
    if(!supabase)return;
    let active=true;
    void supabase.auth.getUser().then(async({data})=>{
      if(!active)return;
      setUser(data.user);
      if(!data.user){setReady(true);return;}
      const{data:role}=await supabase.rpc("current_user_role");
      if(!active)return;
      setAllowed(role==="admin"||role==="teacher");
      setReady(true);
    });
    return()=>{active=false};
  },[supabase]);
  if(!ready)return<main className="correction-route"><section className="panel correction-empty">로그인 정보를 확인하고 있어요…</section></main>;
  if(!supabase)return<main className="correction-route"><section className="panel correction-empty">Supabase 연결 설정이 필요합니다.</section></main>;
  if(!user)return<main className="correction-route"><section className="panel correction-empty"><b>로그인이 필요합니다.</b><a href="/">로그인 화면으로 돌아가기</a></section></main>;
  if(!allowed)return<main className="correction-route"><section className="panel correction-empty"><b>교직원만 첨삭 관리를 사용할 수 있습니다.</b><a href="/">한살매 홈으로 돌아가기</a></section></main>;
  return<main className="correction-route"><header className="correction-route-topbar"><a href="/">‹ 한살매 홈</a><span>첨삭 관리</span></header><div className="correction-route-content"><CorrectionManagementBoard supabase={supabase}/></div></main>;
}
