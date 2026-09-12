"use client";
import {createContext,useContext,useEffect,useRef,useState,type ReactNode} from "react";
import {createPortal} from "react-dom";
import type {SupabaseClient} from "@supabase/supabase-js";
import type {Profile} from "./supabase";
import {useStaffLiveUpdates} from "./use-staff-live-updates";
import {koreanDay,untilNextKoreanDay} from "./schedule-reminder-time";
import styles from "./schedule-reminders.module.css";
type Reminder={source:"calendar"|"special";id:string;version:string;date:string;time:string|null;endTime:string|null;title:string;kind:string;person:string|null;place:string|null;note:string|null;read:boolean};
const key=(r:Reminder)=>`${r.source}:${r.id}:${r.version}`;
type Person={id:string;name:string;role:string};
type State={items:Reminder[];people:Person[];peopleError:string;retryPeople:()=>void;error:string;loading:boolean;refresh:()=>Promise<void>;ack:(r:Reminder)=>Promise<void>;dismiss:(r:Reminder)=>Promise<void>;busy:boolean;open:(r:Reminder)=>void};
const Context=createContext<State|null>(null);
export const useScheduleReminders=()=>useContext(Context);
export function ReminderCheckbox({checked,onChange,disabled=false}:{checked:boolean;onChange:(value:boolean)=>void;disabled?:boolean}){
 return <label className={styles.checkbox}><input type="checkbox" checked={checked} disabled={disabled} onChange={e=>onChange(e.target.checked)}/><span aria-hidden="true"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg></span><span>당일 알림<small>선택한 선생님에게 안내</small></span></label>;
}
export function ReminderRecipients({value,onChange,disabled=false}:{value:string[];onChange:(ids:string[])=>void;disabled?:boolean}){
 const state=useScheduleReminders();const [query,setQuery]=useState("");
 const people=state?.people??[];const roles:Record<string,string>={admin:"관리자",sub_admin:"부관리자",teacher:"선생님",assistant:"조교",manager:"실장님"};
 return <fieldset className={styles.recipients} disabled={disabled}><legend>알림 받을 선생님 <small>{value.length}명</small></legend><p>함께 확인할 선생님·조교를 선택해 주세요. 확인 상태는 각자 저장됩니다.</p>
 <div className={styles.tags}>{value.map(id=><button key={id} type="button" aria-label={`${people.find(p=>p.id===id)?.name??"선택한 교직원"} 알림 대상에서 제외`} onClick={()=>onChange(value.filter(x=>x!==id))}>{people.find(p=>p.id===id)?.name??"선택한 교직원"}<span aria-hidden="true">×</span></button>)}{!value.length&&<small>한 명 이상 선택해 주세요.</small>}</div>
 <input type="search" aria-label="알림 받을 선생님 검색" placeholder="선생님 이름 검색" value={query} onChange={e=>setQuery(e.target.value)}/>
 {state?.peopleError?<p role="alert">{state.peopleError} <button type="button" onClick={state.retryPeople}>다시 시도</button></p>:<div className={styles.people}>{people.filter(p=>p.name.includes(query.trim())).map(p=><button type="button" key={p.id} aria-pressed={value.includes(p.id)} onClick={()=>onChange(value.includes(p.id)?value.filter(id=>id!==p.id):[...value,p.id].sort())}><span><b>{p.name}</b><small>{roles[p.role]??"교직원"}</small></span><i aria-hidden="true">{value.includes(p.id)?"✓":"+"}</i></button>)}{!people.length&&<p>선생님 목록을 확인하고 있어요.</p>}{people.length>0&&!people.some(p=>p.name.includes(query.trim()))&&<p>검색한 선생님이 없습니다.</p>}</div>}
 </fieldset>;
}
export function ScheduleReminderProvider({supabase,profile,children}:{supabase:SupabaseClient;profile:Profile;children:ReactNode}){
 if(!["admin","sub_admin","teacher","assistant","manager"].includes(profile.role))return <>{children}</>;
 return <ActiveProvider key={profile.id} supabase={supabase} profile={profile}>{children}</ActiveProvider>;
}
function ActiveProvider({supabase,profile,children}:{supabase:SupabaseClient;profile:Profile;children:ReactNode}){
 const [items,setItems]=useState<Reminder[]>([]),[popup,setPopup]=useState<string[]>([]),[selected,setSelected]=useState<Reminder|null>(null),[error,setError]=useState(""),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false);
 const detailRef=useRef<HTMLElement|null>(null);
 const [people,setPeople]=useState<Person[]>([]),[peopleError,setPeopleError]=useState(""),[peopleAttempt,setPeopleAttempt]=useState(0);
 useEffect(()=>{let active=true;void supabase.rpc("staff_schedule_reminder_people").then(({data,error:failure})=>{if(!active)return;if(failure)setPeopleError("선생님 목록을 불러오지 못했습니다.");else{setPeople((data??[]) as Person[]);setPeopleError("");}});return()=>{active=false;};},[supabase,peopleAttempt]);
 const refresh=useStaffLiveUpdates(supabase,`reminders-${profile.id}`,`key=eq.reminders:${profile.id}`,async(_batch,active)=>{
  const {data,error:failure}=await supabase.rpc("staff_schedule_reminders",{p_claim:true});
  if(!active())return;if(failure)throw failure;
  const next=(data?.items??[]) as Reminder[];setItems(next);setLoading(false);setError("");
  const eligible=new Set(next.filter(r=>!r.read&&r.date===koreanDay()).map(key));
  setPopup(current=>[...new Set([...current,...(data?.popup??[])])].filter(id=>eligible.has(id)));
  setSelected(current=>current?next.find(r=>key(r)===key(current))??null:null);
 },e=>{setLoading(false);setError((e as {message?:string}).message??"일정 알림을 불러오지 못했습니다.");},true);
 useEffect(()=>{let timer:ReturnType<typeof setTimeout>;let active=true;const schedule=()=>{timer=setTimeout(()=>{if(active){setPopup([]);void refresh();schedule();}},untilNextKoreanDay());};schedule();return()=>{active=false;clearTimeout(timer);};},[refresh]);
 const selectedId=selected?.id;
 useEffect(()=>{if(!selectedId)return;const previous=document.activeElement as HTMLElement|null;const close=(e:KeyboardEvent)=>{if(e.key==="Escape")setSelected(null);if(e.key==="Tab"){const buttons=detailRef.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)');if(!buttons?.length)return;const first=buttons[0],last=buttons[buttons.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}};window.addEventListener("keydown",close);return()=>{window.removeEventListener("keydown",close);previous?.focus();};},[selectedId]);
 const ack=async(r:Reminder)=>{setBusy(true);try{const {error:failure}=await supabase.rpc("staff_ack_schedule_reminder",{p_source:r.source,p_id:r.id,p_version:r.version});if(failure)throw failure;setItems(current=>current.map(x=>key(x)===key(r)?{...x,read:true}:x));setPopup(current=>current.filter(id=>id!==key(r)));setSelected(null);setError("");}catch(e){setError((e as {message?:string}).message??"확인 상태를 저장하지 못했습니다.");}finally{setBusy(false);}};
 const dismiss=async(r:Reminder)=>{if(busy||!r.read)return;setBusy(true);try{const {error:failure}=await supabase.rpc("staff_dismiss_schedule_reminder",{p_source:r.source,p_id:r.id,p_version:r.version});if(failure)throw failure;setItems(current=>current.filter(x=>key(x)!==key(r)));setPopup(current=>current.filter(id=>id!==key(r)));setSelected(current=>current&&key(current)===key(r)?null:current);setError("");}catch(e){setError((e as {message?:string}).message??"알림을 삭제하지 못했습니다.");}finally{setBusy(false);}};
 const today=items.filter(r=>popup.includes(key(r))),first=today[0];
 return <Context.Provider value={{items,people,peopleError,retryPeople:()=>setPeopleAttempt(n=>n+1),error,loading,refresh,ack,dismiss,busy,open:setSelected}}>{children}
 {typeof document!=="undefined"&&first&&!selected&&createPortal(<aside className={styles.toast} role="status"><button className={styles.close} aria-label="알림 카드 닫기" onClick={()=>setPopup([])}>×</button><small>오늘의 일정 · {today.length}건</small><h3>{today.length>1?"오늘 확인할 일정이 있어요":`${first.kind} 일정이 있어요`}</h3><p>{first.time??"시간 미지정"} · {first.title}</p>{first.person&&<p className={styles.person}>{first.person}</p>}{error&&<p role="alert">{error}</p>}<div className={styles.actions}><button onClick={()=>setSelected(first)}>일정 확인</button><button disabled={busy} onClick={()=>void ack(first)}>{busy?"저장 중…":"확인했어요"}</button></div></aside>,document.body)}
 {typeof document!=="undefined"&&selected&&createPortal(<div className={styles.backdrop} onMouseDown={e=>{if(e.target===e.currentTarget)setSelected(null);}}><section ref={detailRef} className={styles.detail} role="dialog" aria-modal="true" aria-labelledby="schedule-reminder-title"><header><small>{selected.kind} 알림</small><button autoFocus aria-label="일정 상세 닫기" onClick={()=>setSelected(null)}>×</button><h2 id="schedule-reminder-title">{selected.title}</h2></header><div className={styles.body}><dl><dt>일시</dt><dd>{selected.date} · {selected.time?`${selected.time}${selected.endTime?`–${selected.endTime}`:""}`:"시간 미지정"}</dd>{selected.person&&<><dt>학생·상담자</dt><dd>{selected.person}</dd></>}{selected.place&&<><dt>장소</dt><dd>{selected.place}</dd></>}</dl><h3>메모</h3><p>{selected.note||"등록된 메모가 없습니다."}</p>{error&&<p role="alert">{error}</p>}</div><footer><button onClick={()=>setSelected(null)}>닫기</button><button disabled={busy} onClick={()=>void ack(selected)}>{busy?"저장 중…":"확인했어요"}</button></footer></section></div>,document.body)}
 </Context.Provider>;
}
export function ScheduleReminderList(){
 const state=useScheduleReminders();
 if(!state)return null;
 return <>
  <div className="notification-toolbar"><span>최근 30일 · 미확인 {state.items.filter(r=>!r.read).length}건</span><button type="button" className="notification-refresh" onClick={()=>void state.refresh()}><span aria-hidden="true">↻</span>새로고침</button></div>
  <div className="notification-list">
   {state.error&&<p role="alert">{state.error}</p>}
   {state.loading?<p>일정 알림을 확인하고 있어요.</p>:!state.items.length?<p>등록된 일정 알림이 없습니다.<br/>당일 알림을 켠 일정이 여기에 모입니다.</p>:state.items.map(r=><div className={styles.entry} key={key(r)}><button className={`${styles.item} ${r.read?styles.read:""}`} onClick={()=>state.open(r)}><span>{r.kind}<em>{r.read?"확인 완료":"미확인"}</em></span><b>{r.title}</b><small>{r.date} · {r.time??"시간 미지정"}{r.place?` · ${r.place}`:""}</small>{r.person&&<p>{r.person}</p>}</button>{r.read&&<button className={styles.deleteReminder} disabled={state.busy} aria-label={`${r.title} 알림 삭제`} onClick={()=>void state.dismiss(r)}>알림 삭제</button>}</div>)}
  </div>
 </>;
}
