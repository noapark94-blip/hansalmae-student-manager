"use client";
import { useState } from "react";
import { correctionSlots, defaultCorrectionEnd, isStandardCorrectionTime } from "./correction-time";
import "./correction-time-picker.css";
export function CorrectionTimePicker({weekday,start,end,onChange}:{weekday:number;start:string;end:string;onChange:(start:string,end:string)=>void}){
 const [manual,setManual]=useState(!isStandardCorrectionTime(weekday,start,end));
 const custom=manual||!isStandardCorrectionTime(weekday,start,end);
 return <div className="correction-time-picker"><span className="correction-time-label">시간</span>
 <div className="correction-time-modes" role="group" aria-label="시간 설정 방식">
 <button type="button" aria-pressed={!custom} onClick={()=>{setManual(false);const slot=correctionSlots(weekday)[0];onChange(slot[0],slot[1]);}}>기본 시간</button>
 <button type="button" aria-pressed={custom} onClick={()=>setManual(true)}>직접 설정</button></div>
 {custom?<><div className="correction-time-inputs"><label>시작<input required type="time" value={start} onChange={e=>onChange(e.target.value,defaultCorrectionEnd(e.target.value))}/></label><span aria-hidden="true">—</span><label>종료<input required type="time" value={end} onChange={e=>onChange(start,e.target.value)}/></label></div><p>시작 시간 변경 시 종료는 90분 뒤로 설정됩니다. 종료 시간도 바꿀 수 있어요.</p></>:<select aria-label="기본 첨삭 시간" value={start} onChange={e=>{const slot=correctionSlots(weekday).find(s=>s[0]===e.target.value)!;onChange(slot[0],slot[1]);}}>{correctionSlots(weekday).map(s=><option key={s[0]} value={s[0]}>{s[0]}–{s[1]}</option>)}</select>}
 </div>;
}
