"use client";
import { useEffect, useState } from "react";
import styles from './family-loading.module.css';

export function FamilyLoading({fullScreen=false}:{fullScreen?:boolean}) {
  const [visible,setVisible]=useState(false);
  useEffect(()=>{const timer=window.setTimeout(()=>setVisible(true),250);return()=>window.clearTimeout(timer);},[]);
  if(!visible)return null;
  return <section className={`${styles.loading} ${fullScreen?styles.full:styles.inline}`} role="status" aria-live="polite" aria-label="화면을 불러오는 중이에요">
    <div className={styles.identity} aria-hidden="true"><span className={styles.mark}><img src="/app-icon-192-v13.png" alt="" width={48} height={48}/></span><span className={styles.brand}>한살매 <b>수업노트</b></span></div>
    <div className={styles.dots} aria-hidden="true"><i/><i/><i/></div>
    <p aria-hidden="true">화면을 불러오는 중이에요</p>
    {!fullScreen&&<div className={styles.skeleton} aria-hidden="true"><div><i/><i/><i/></div><div><i/><i/></div></div>}
  </section>;
}
