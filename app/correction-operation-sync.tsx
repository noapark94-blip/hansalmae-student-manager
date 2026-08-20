"use client";

import { useEffect } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Assignment={id:string;studentId:string;studentName:string;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string};
type Exception={id:string;assignmentId:string;originalDate:string;kind:"move"|"cancel"|"extra";targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null};
type Board={assignments:Assignment[];exceptions:Exception[]};
type Operational={assignment:Assignment;date:string;startTime:string;kind:"fixed"|"move"|"extra";exception?:Exception};

const WEEKDAYS=["월","화","수","목","금","토","일"];

export function CorrectionOperationSync({supabase}:{supabase:SupabaseClient}){
  useEffect(()=>{
    let disposed=false;
    let queued=false;
    const boardCache=new Map<string,Promise<Board|null>>();

    const getBoard=(anchor:string)=>{
      const monday=weekMonday(anchor);
      let cached=boardCache.get(monday);
      if(!cached){
        cached=supabase.rpc("correction_management_board",{p_anchor:monday}).then(({data,error})=>error?null:data as Board);
        boardCache.set(monday,cached);
      }
      return cached;
    };

    const syncFixedTimetable=()=>{
      const board=document.querySelector<HTMLElement>(".correction-week-board");
      if(!board)return;
      board.querySelectorAll<HTMLElement>(".correction-student.moved,.correction-student.extra").forEach(card=>card.style.setProperty("display","none","important"));
      board.querySelectorAll<HTMLElement>(".correction-student.ghost").forEach(card=>{
        card.style.setProperty("display","flex","important");
        card.style.setProperty("opacity","1","important");
        card.style.setProperty("background","#faf7f8","important");
        card.style.setProperty("border","0","important");
        card.querySelector("em")?.remove();
        const small=card.querySelector("small");
        if(small)small.textContent="정규 일정";
      });
      board.querySelectorAll<HTMLElement>(".correction-day").forEach(day=>{
        const count=[...day.querySelectorAll<HTMLElement>(".correction-student")].filter(card=>getComputedStyle(card).display!=="none").length;
        const badge=day.querySelector<HTMLElement>(":scope > header > em");
        if(badge)badge.textContent=`${count}명`;
      });
    };

    const syncWorkBoard=async()=>{
      const strip=document.querySelector<HTMLElement>(".correction-week-strip");
      if(!strip)return;
      const buttons=[...strip.querySelectorAll<HTMLButtonElement>(":scope > button")];
      if(buttons.length!==7)return;
      const monday=inferMonday(buttons.map(button=>Number(button.querySelector("b")?.textContent||0)));
      if(!monday)return;
      const board=await getBoard(monday);if(disposed||!board)return;
      const operational=new Map<string,Operational[]>();
      for(let i=0;i<7;i++){const date=addDays(monday,i);operational.set(date,buildOperational(board,date));}

      buttons.forEach((button,index)=>{
        const date=addDays(monday,index);
        const rows=operational.get(date)??[];
        const nameEls=[...button.querySelectorAll<HTMLElement>("em")];
        const used=new Set<number>();
        nameEls.forEach(el=>{
          const base=el.dataset.baseStudentName||el.childNodes[0]?.textContent?.trim()||el.textContent?.trim()||"";
          el.dataset.baseStudentName=base;
          el.querySelector(".correction-change-badge")?.remove();
          const rowIndex=rows.findIndex((row,i)=>!used.has(i)&&row.assignment.studentName===base&&row.kind!=="fixed");
          if(rowIndex<0)return;
          used.add(rowIndex);
          const row=rows[rowIndex];
          const badge=document.createElement("span");
          badge.className=`correction-change-badge ${row.kind}`;
          badge.textContent=row.kind==="move"?"변경":"추가";
          el.appendChild(badge);
        });
      });

      const selectedIndex=buttons.findIndex(button=>button.classList.contains("active"));
      if(selectedIndex<0)return;
      const selectedDate=addDays(monday,selectedIndex);
      const selectedRows=operational.get(selectedDate)??[];
      document.querySelectorAll<HTMLElement>(".correction-learning-rows article").forEach(article=>{
        const name=article.querySelector<HTMLElement>(".learning-student button b")?.textContent?.trim();
        if(!name)return;
        const info=article.querySelector<HTMLElement>(".learning-student > small")?.textContent||"";
        const row=selectedRows.find(item=>item.assignment.studentName===name&&info.includes(item.assignment.subject));
        const student=article.querySelector<HTMLElement>(".learning-student");
        student?.querySelector(".correction-change-badge")?.remove();
        student?.querySelector(".correction-change-origin")?.remove();
        if(!row||row.kind==="fixed"||!student)return;
        const badge=document.createElement("span");
        badge.className=`correction-change-badge detail ${row.kind}`;
        badge.textContent=row.kind==="move"?"변경 일정":"추가 첨삭";
        student.appendChild(badge);
        const detail=document.createElement("small");
        detail.className="correction-change-origin";
        if(row.kind==="move"&&row.exception){
          const originalDay=WEEKDAYS[isoWeekday(row.exception.originalDate)-1];
          detail.textContent=`기존 ${originalDay} ${row.assignment.startTime.slice(0,5)} → ${WEEKDAYS[isoWeekday(selectedDate)-1]} ${row.startTime.slice(0,5)}`;
        }else detail.textContent="정규 일정 외 추가 첨삭";
        student.appendChild(detail);
      });
    };

    const syncMonthCalendar=async()=>{
      const modal=document.querySelector<HTMLElement>(".correction-month-modal");
      if(!modal)return;
      const title=modal.querySelector<HTMLElement>(".correction-month-toolbar strong")?.textContent||"";
      const match=title.match(/(\d{4})년\s*(\d{1,2})월/);if(!match)return;
      const month=`${match[1]}-${String(Number(match[2])).padStart(2,"0")}-01`;
      const dates=calendarDays(month);
      const boards=await Promise.all([...new Set(dates.map(weekMonday))].map(getBoard));
      if(disposed)return;
      const boardByMonday=new Map<string,Board>();
      [...new Set(dates.map(weekMonday))].forEach((monday,i)=>{const board=boards[i];if(board)boardByMonday.set(monday,board)});
      const cells=[...modal.querySelectorAll<HTMLButtonElement>(".correction-month-grid > button")];
      cells.forEach((cell,index)=>{
        const date=dates[index];if(!date)return;
        const board=boardByMonday.get(weekMonday(date));if(!board)return;
        const rows=buildOperational(board,date);
        const used=new Set<number>();
        cell.querySelectorAll<HTMLElement>("em").forEach(el=>{
          const base=el.dataset.baseStudentName||el.childNodes[0]?.textContent?.trim()||el.textContent?.trim()||"";
          el.dataset.baseStudentName=base;
          el.querySelector(".correction-change-badge")?.remove();
          const rowIndex=rows.findIndex((row,i)=>!used.has(i)&&row.assignment.studentName===base&&row.kind!=="fixed");
          if(rowIndex<0)return;used.add(rowIndex);
          const row=rows[rowIndex];const badge=document.createElement("span");
          badge.className=`correction-change-badge ${row.kind}`;badge.textContent=row.kind==="move"?"변경":"추가";el.appendChild(badge);
        });
      });
    };

    const sync=()=>{syncFixedTimetable();void syncWorkBoard();void syncMonthCalendar()};
    const requestSync=()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;sync()})};
    sync();
    const observer=new MutationObserver(requestSync);observer.observe(document.body,{childList:true,subtree:true,characterData:true,attributes:true,attributeFilter:["class"]});
    return()=>{disposed=true;observer.disconnect()};
  },[supabase]);

  return <style>{`
    .correction-change-badge{display:inline-flex;align-items:center;margin-left:5px;padding:1px 5px;border-radius:999px;font-size:9px;font-style:normal;font-weight:800;line-height:1.5;vertical-align:middle;white-space:nowrap}
    .correction-change-badge.move{background:#fff0df;color:#b76518;border:1px solid #f2c891}
    .correction-change-badge.extra{background:#eaf7ef;color:#28744b;border:1px solid #b9dfc8}
    .correction-change-badge.detail{width:max-content;margin:5px 0 0;padding:3px 7px;font-size:10px}
    .correction-change-origin{display:block!important;margin-top:3px!important;color:#a26a45!important;font-size:10px!important;line-height:1.35!important}
    .correction-week-board .correction-student.ghost small{color:#94868d!important}
  `}</style>;
}

function buildOperational(board:Board,date:string):Operational[]{
  const weekday=isoWeekday(date),rows:Operational[]=[];
  for(const assignment of board.assignments??[]){
    if(assignment.weekday!==weekday)continue;
    const exception=(board.exceptions??[]).find(item=>item.assignmentId===assignment.id&&item.originalDate===date&&(item.kind==="move"||item.kind==="cancel"));
    if(!exception)rows.push({assignment,date,startTime:assignment.startTime,kind:"fixed"});
  }
  for(const exception of board.exceptions??[]){
    if((exception.kind!=="move"&&exception.kind!=="extra")||exception.targetDate!==date||!exception.targetStartTime)continue;
    const assignment=(board.assignments??[]).find(item=>item.id===exception.assignmentId);if(assignment)rows.push({assignment,date,startTime:exception.targetStartTime,kind:exception.kind,exception});
  }
  return rows.sort((a,b)=>a.startTime.localeCompare(b.startTime)||a.assignment.studentName.localeCompare(b.assignment.studentName,"ko"));
}
function isoWeekday(value:string){const d=new Date(`${value}T12:00:00+09:00`);const day=d.getUTCDay();return day===0?7:day}
function addDays(value:string,days:number){const d=new Date(`${value}T12:00:00+09:00`);d.setUTCDate(d.getUTCDate()+days);return formatDate(d)}
function weekMonday(value:string){return addDays(value,1-isoWeekday(value))}
function formatDate(d:Date){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(d)}
function inferMonday(dayNumbers:number[]){
  if(dayNumbers.length!==7||dayNumbers.some(n=>!n))return null;
  const today=formatDate(new Date());let best:string|null=null,bestDistance=Infinity;
  for(let offset=-370;offset<=370;offset++){
    const candidate=addDays(today,offset);if(isoWeekday(candidate)!==1)continue;
    if(dayNumbers.every((n,i)=>Number(addDays(candidate,i).slice(8))===n)){
      const distance=Math.abs(offset);if(distance<bestDistance){best=candidate;bestDistance=distance}
    }
  }
  return best;
}
function calendarDays(month:string){const first=new Date(`${month}T12:00:00+09:00`);const start=addDays(formatDate(first),1-isoWeekday(formatDate(first)));const last=new Date(first);last.setUTCMonth(last.getUTCMonth()+1);last.setUTCDate(0);const end=addDays(formatDate(last),7-isoWeekday(formatDate(last)));const out:string[]=[];for(let day=start;;day=addDays(day,1)){out.push(day);if(day===end)break}return out}
