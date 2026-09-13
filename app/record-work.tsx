"use client";
import {createContext,useCallback,useContext,useEffect,useRef,useState,type ReactNode} from 'react';
import dynamic from 'next/dynamic';
import {createPortal} from 'react-dom';
import type {SupabaseClient} from '@supabase/supabase-js';
import type {Profile} from './supabase';
import {appConfirm} from './app-dialog';
import {filterWork,workPeriod,recordWorkDate,syncRecordToast,type RecordWorkItem} from './record-work-model';
import styles from './record-work.module.css';
const Regular=dynamic(()=>import('./teacher-class-workspace').then(m=>m.TeacherClassWorkspace));
const Special=dynamic(()=>import('./special-lesson-learning-board').then(m=>m.SpecialLessonLearningBoard));
const Correction=dynamic(()=>import('./correction-work-board').then(m=>m.CorrectionWorkBoard));
type State={today:string;items:RecordWorkItem[];loading:boolean;error:string;refresh:()=>Promise<void>;open:(item:RecordWorkItem)=>void;profile:Profile;supabase:SupabaseClient};
const Context=createContext<State|null>(null);
export function RecordWorkProvider({supabase,profile,children}:{supabase:SupabaseClient;profile:Profile;children:ReactNode}){
 if(!['admin','sub_admin','teacher','assistant','manager'].includes(profile.role))return <>{children}</>;
 return <Active key={profile.id} supabase={supabase} profile={profile}>{children}</Active>;
}
function Active({supabase,profile,children}:{supabase:SupabaseClient;profile:Profile;children:ReactNode}){
 const [today,setToday]=useState(()=>workPeriod().today);
 const [items,setItems]=useState<RecordWorkItem[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const [selected,setSelected]=useState<RecordWorkItem|null>(null),[toast,setToast]=useState<{count:number;requested:boolean}|null>(null),[listOpen,setListOpen]=useState(false);
 const alive=useRef(true),inFlight=useRef(false),dialog=useRef<HTMLElement|null>(null);
 const refresh=useCallback(async()=>{
  if(inFlight.current||document.visibilityState==='hidden')return;
  inFlight.current=true;
  try{const {today,from}=workPeriod();setToday(today);const result=await supabase.rpc('staff_record_worklist',{p_from:from,p_to:today});if(!alive.current)return;if(result.error)throw result.error;if(!Array.isArray(result.data))throw new Error('기록 목록 응답을 확인하지 못했습니다.');
   setItems(result.data);setError('');setToast(previous=>syncRecordToast(previous,result.data,profile.id));
   if(result.data.some((x:RecordWorkItem)=>x.due&&x.owners.some(p=>p.id===profile.id))){const claim=await supabase.rpc('staff_claim_record_reminder');if(alive.current&&!claim.error&&claim.data)setToast(syncRecordToast(claim.data,result.data,profile.id));}
   else setToast(null);
  }catch(e){if(alive.current){setError((e as {message?:string}).message??'기록 목록을 불러오지 못했습니다.');setItems([]);setToast(null);}}
  finally{inFlight.current=false;if(alive.current)setLoading(false);}
 },[supabase,profile.id]);
 useEffect(()=>{alive.current=true;void refresh();const resume=()=>void refresh();const timer=window.setInterval(resume,120000);window.addEventListener('focus',resume);window.addEventListener('online',resume);document.addEventListener('visibilitychange',resume);return()=>{alive.current=false;clearInterval(timer);window.removeEventListener('focus',resume);window.removeEventListener('online',resume);document.removeEventListener('visibilitychange',resume);};},[refresh]);
 const close=useCallback(async()=>{if(selected&&!await appConfirm({eyebrow:'기록 화면',title:'기록 화면을 닫을까요?',copy:'입력한 내용은 해당 수업의 저장 버튼으로 저장해 주세요.',confirmLabel:'닫기'}))return;setSelected(null);setListOpen(false);void refresh();},[selected,refresh]);
 useEffect(()=>{if(!selected&&!listOpen)return;const previous=document.activeElement as HTMLElement|null;const old=document.body.style.overflow;document.body.style.overflow='hidden';dialog.current?.focus();const key=(e:KeyboardEvent)=>{if(document.querySelector('[role="alertdialog"]')||Array.from(document.querySelectorAll('[role="dialog"]')).some(n=>n!==dialog.current&&!dialog.current?.contains(n)))return;if(e.key==='Escape'){e.stopPropagation();void close();}if(e.key==='Tab'){const nodes=Array.from(dialog.current?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),[tabindex="0"]')??[]).filter(x=>x.getClientRects().length);const first=nodes[0],last=nodes.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}};document.addEventListener('keydown',key);return()=>{document.body.style.overflow=old;document.removeEventListener('keydown',key);previous?.focus();};},[selected,listOpen,close]);
 return <Context.Provider value={{today,items,loading,error,refresh,open:setSelected,profile,supabase}}>{children}
 {toast&&!listOpen&&!selected&&createPortal(<aside className={styles.toast} role="status"><button aria-label="기록 알림 닫기" onClick={()=>setToast(null)}>×</button><small>{toast.requested?'원장님 기록 요청':'오늘의 기록 마무리'}</small><strong>아직 마무리할 기록이 있어요</strong><p>내 담당 기록 {toast.count}건 · 정규·첨삭·보강·추가</p><button onClick={()=>{setToast(null);setListOpen(true);}}>남은 기록 확인 →</button></aside>,document.body)}
 {(selected||listOpen)&&createPortal(<div className={styles.backdrop}><section ref={dialog} tabIndex={-1} className={styles.dialog} role="dialog" aria-modal="true" aria-label="기록 마무리"><header><div><small>기록 마무리</small><h2>{selected?`${selected.studentName} · ${selected.kind}`:'내 남은 기록'}</h2>{selected&&<p>{selected.date} · {selected.time??'시간 미정'} · {selected.title}</p>}</div><button onClick={()=>void close()} aria-label="기록 마무리 닫기">닫기 ×</button></header><div className={styles.editor}>
 {!selected?<RecordWorkPanel expanded allDates/>:selected.source==='correction'?<Correction key={selected.key} supabase={supabase} initialDate={selected.date} focusStudentId={selected.studentId}/>:selected.sessionId?<Special key={selected.key} embedded supabase={supabase} profile={profile} sessionId={selected.sessionId} lessonKind={selected.kind.includes('보강')?'makeup':'additional'} onClose={()=>void close()} onAttendanceChange={()=>refresh()}/>:selected.classId?<Regular key={selected.key} supabase={supabase} profile={profile} lessonTarget={{classId:selected.classId,date:selected.date,requestId:1}}/>:<p>수업 연결 정보를 찾을 수 없습니다.</p>}
 </div></section></div>,document.body)}
 </Context.Provider>;
}
export function RecordWorkPanel({expanded=false,allDates=false}:{expanded?:boolean;allDates?:boolean}){
 const state=useContext(Context);const [show,setShow]=useState(expanded),[dateSelection,setDate]=useState(allDates?'':'today'),[kind,setKind]=useState('all'),[owner,setOwner]=useState('all'),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 if(!state)return null;
 const {today,items,loading,error,refresh,open,profile,supabase}=state,date=recordWorkDate(dateSelection,today),admin=profile.role==='admin';
 const rows=filterWork(items,date,kind,owner,profile.id),due=rows.filter(x=>x.due),pending=rows.filter(x=>!x.due);
 const owners=Array.from(new Map(items.flatMap(x=>x.owners).map(p=>[p.id,p])).values()).sort((a,b)=>a.name.localeCompare(b.name));
 const request=async()=>{if(busy||!date)return;setBusy(true);setMessage('');try{const r=await supabase.rpc('staff_request_missing_records',{p_date:date,p_recipient:owner==='all'?null:owner==='mine'?profile.id:owner});if(r.error)throw r.error;setMessage(`${r.data.sent}명에게 앱 알림을 요청했습니다.${r.data.cooldown?` ${r.data.cooldown}명은 30분 내 요청이 있어 중복 알림을 생략했습니다.`:''}`);await refresh();}catch(e){setMessage((e as {message?:string}).message??'알림 요청에 실패했습니다.');}finally{setBusy(false);}};
 return <section className={styles.panel} aria-label="미완료 수업 기록"><div className={styles.top}><button className={styles.summary} onClick={()=>setShow(!show)} aria-expanded={show}><span className={styles.icon}>✓</span><span><small>RECORD CHECK</small><strong>{admin?'수업 기록 마무리':'내 수업 기록 마무리'}</strong><em>{loading?'기록 확인 중':error?'조회 상태 확인 필요':`${items.filter(x=>x.due).length}건 남음 · 최근 7일`}</em></span><span className={styles.chevron}>{show?'⌃':'⌄'}</span></button><button className={styles.refresh} onClick={()=>void refresh()} disabled={loading}>새로고침</button></div>
 {show&&<><p className={styles.hint}>수업이 끝난 뒤 출결과 완료 처리가 필요한 기록입니다. 시험·숙제 공란은 누락으로 보지 않아요.</p><div className={styles.filters}><label>기록 날짜<select value={dateSelection==='today'||(dateSelection!==''&&dateSelection!==date)?'today':dateSelection} onChange={e=>setDate(e.target.value)}><option value="">최근 7일 전체</option>{Array.from({length:7},(_,i)=>{const d=new Date(today+'T12:00:00Z');d.setUTCDate(d.getUTCDate()-i);const v=d.toISOString().slice(0,10);return <option key={v} value={i===0?'today':v}>{i===0?'오늘 · ':''}{v.slice(5).replace('-','월 ')}일</option>})}</select></label>{admin&&<label>담당자<select value={owner} onChange={e=>setOwner(e.target.value)}><option value="all">전체 담당자</option><option value="mine">내 기록</option>{owners.filter(p=>p.id!==profile.id).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>}<div className={styles.tabs} role="group" aria-label="수업 종류">{[['all','전체'],['regular','정규'],['correction','첨삭'],['makeup','보강'],['additional','추가']].map(([v,label])=><button key={v} aria-pressed={kind===v} onClick={()=>setKind(v)}>{label}</button>)}</div></div>
 {error?<p className={styles.error} role="alert">{error} <button onClick={()=>void refresh()}>다시 시도</button></p>:loading?<p className={styles.empty}>기록을 확인하고 있어요.</p>:<><div className={styles.status}><strong>마무리 필요 <b>{due.length}</b>건</strong><span>진행·예정 {pending.length}건</span>{admin&&<button disabled={busy||!date||!due.length} onClick={()=>void request()}>{busy?'요청 중…':'담당자에게 기록 요청'}</button>}</div>{admin&&<p className={styles.hint}>알림은 선택한 날짜·담당자의 모든 수업 종류에 적용됩니다. 담당자가 없으면 알림을 보낼 수 없습니다.</p>}
 {!due.length&&<div className={styles.empty}><span>✓</span><strong>마무리할 기록이 없습니다</strong><p>{pending.length?'아직 끝나지 않은 수업은 아래에 모아두었어요.':'선택한 범위의 기록을 모두 확인했어요.'}</p></div>}
 <div className={styles.rows}>{[...due,...pending].map(item=><article key={item.key} className={!item.due?styles.scheduled:''}><div className={styles.when}><b>{item.time??'시간 미정'}</b><small>{item.date.slice(5).replace('-','.')}</small></div><div className={styles.student}><strong>{item.studentName}</strong><span>{item.kind} · {item.title}</span><small>{item.owners.map(p=>p.name).join(' · ')||'담당자 미지정'}{item.owners.length>1?' · 공동 담당':''}</small></div><span className={styles.reason}>{item.due?item.reason:'진행·예정'}</span><button onClick={()=>open(item)} aria-label={`${item.studentName} ${item.date} ${item.kind} 기록하기`}>기록하기 <span aria-hidden="true">→</span></button></article>)}</div></>}
 {message&&<p className={styles.message} role="status">{message}</p>}<footer className={styles.hint}>화면이 열려 있으면 2분마다 갱신합니다. 자동 안내는 수업 종료 후·21:30 이후 각 한 번 표시됩니다.</footer></>}
 </section>;
}
