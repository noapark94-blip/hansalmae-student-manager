"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import confirmStyles from "./message-confirm.module.css";

type Student={id:string;name:string;school:string|null;grade:string|null};
type Staff={id:string;name:string};
type Assistant={id:string;name:string};
type SlotAssistant={weekday:number;startTime:string;assistantId:string;assistantName:string};
type AssistantBoard={canManage:boolean;assistants:Assistant[];assignments:SlotAssistant[]};
type Assignment={id:string;studentId:string;studentName:string;school:string|null;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string;validFrom:string;validUntil:string|null;tutorId:string|null;tutorName:string|null;supervisorId:string|null;supervisorName:string|null;note:string|null;isDateOverride?:boolean};
type Exception={id:string;assignmentId:string;originalDate:string;kind:"move"|"cancel"|"extra";targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null;note:string|null};
type Board={weekStart:string;students:Student[];staff:Staff[];assignments:Assignment[];exceptions:Exception[]};
type Occurrence={key:string;assignment:Assignment;date:string;startTime:string;endTime:string;state:"fixed"|"moved"|"extra";exception?:Exception};
type EditorState={row?:Assignment;weekday?:number;slot?:string;overrideDate?:string}|null;
type SubjectFilter="전체"|Assignment["subject"];
type SlotRosterState={day:string;date:string;start:string;end:string;entries:{key:string;assignment:Assignment;state:Occurrence["state"]|"ghost"}[]}|null;

const days=["월","화","수","목","금","토","일"];
const weekdaySlots=[["14:30","16:00"],["16:00","17:30"],["17:30","19:00"],["19:00","20:30"],["20:30","22:00"]] as const;
const weekendSlots=[["09:30","11:00"],["11:00","12:30"],["12:30","14:00"],["14:00","15:30"],["15:30","17:00"]] as const;

export function CorrectionManagementBoard({supabase}:{supabase:SupabaseClient}){
  const[anchor,setAnchor]=useState(koreaToday());
  const[data,setData]=useState<Board|null>(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const[editor,setEditor]=useState<EditorState>(null);
  const[action,setAction]=useState<{assignment:Assignment;date:string}|null>(null);
  const[selectedDay,setSelectedDay]=useState(1);
  const[subjectFilter,setSubjectFilter]=useState<SubjectFilter>("전체");
  const[slotRoster,setSlotRoster]=useState<SlotRosterState>(null);
  const[assistantData,setAssistantData]=useState<AssistantBoard|null>(null);
  const[assistantEditorOpen,setAssistantEditorOpen]=useState(false);

  const load=useCallback(async()=>{
    setLoading(true);
    setError("");
    const[boardResult,assistantResult]=await Promise.all([
      supabase.rpc("correction_management_board_v2",{p_anchor:anchor}),
      supabase.rpc("correction_slot_assistant_board")
    ]);
    if(boardResult.error){setError(`첨삭 시간표를 불러오지 못했습니다. ${boardResult.error.message}`);setData(null);}
    else setData(boardResult.data as Board);
    if(assistantResult.error){setError(current=>current||`담당 조교 정보를 불러오지 못했습니다. ${assistantResult.error.message}`);setAssistantData(null);}
    else setAssistantData(assistantResult.data as AssistantBoard);
    setLoading(false);
  },[anchor,supabase]);

  useEffect(()=>{void load();},[load]);
  useEffect(()=>{
    const refresh=()=>void load();
    window.addEventListener("hansalmae-correction-assignments-changed",refresh);
    return()=>window.removeEventListener("hansalmae-correction-assignments-changed",refresh);
  },[load]);
  const occurrences=useMemo(()=>buildOccurrences(data),[data]);
  const movedFrom=useMemo(()=>new Map<string,Exception>(),[]);
  const assistantsBySlot=useMemo(()=>{
    const result=new Map<string,SlotAssistant[]>();
    for(const item of assistantData?.assignments??[]){const key=`${item.weekday}-${item.startTime.slice(0,5)}`;result.set(key,[...(result.get(key)??[]),item]);}
    return result;
  },[assistantData]);
  const changeWeek=(delta:number)=>setAnchor(current=>addDays(current,delta));

  return <>
    <div className="page-heading correction-heading">
      <div><p className="eyebrow">한살매 첨삭 운영</p><h1>첨삭 관리</h1><p>고정 첨삭일은 유지하고, 이번 주 변경·취소·추가만 예외 일정으로 관리합니다.</p></div>
      <button className="primary" onClick={()=>setEditor({})}>＋ 학생 추가</button>
    </div>
    <div className="correction-week-toolbar"><button onClick={()=>changeWeek(-7)}>‹ 이전 주</button><strong>{data?formatWeek(data.weekStart):"주간 시간표"}</strong><button onClick={()=>changeWeek(7)}>다음 주 ›</button><button className="today" onClick={()=>setAnchor(koreaToday())}>이번 주</button></div>
    {error&&<p className="attendance-error">{error}</p>}
    {assistantData?.canManage?<div className="correction-assistant-actions"><button type="button" onClick={()=>setAssistantEditorOpen(true)}><span>담당 조교 설정</span><small>요일·시간대별 배정</small></button></div>:null}
    <nav className="correction-mobile-days">{days.map((day,index)=><button key={day} className={selectedDay===index+1?"active":""} onClick={()=>setSelectedDay(index+1)}>{day}</button>)}</nav>
    <nav className="correction-timetable-subject-filter" aria-label="첨삭 과목 필터">{(["전체","국어","영어","수학"] as SubjectFilter[]).map(subject=>{const count=subject==="전체"?occurrences.length:occurrences.filter(item=>item.assignment.subject===subject).length;return <button type="button" key={subject} className={subjectFilter===subject?"active":""} onClick={()=>setSubjectFilter(subject)}><span>{subject}</span><em>{count}명</em></button>})}</nav>
    {loading?<section className="panel correction-empty">첨삭 시간표를 불러오는 중이에요…</section>:!data?<section className="panel correction-empty">첨삭 시간표를 표시할 수 없습니다.</section>:<section className="correction-week-board">{days.map((day,index)=>{
      const weekday=index+1;
      const date=addDays(data.weekStart,index);
      const slots=weekday<=5?weekdaySlots:weekendSlots;
      return <section key={day} className={`correction-day ${selectedDay===weekday?"mobile-active":""}`}>
        <header><span><b>{day}요일</b><small>{formatShortDate(date)}</small></span><em>{occurrences.filter(item=>item.date===date&&(subjectFilter==="전체"||item.assignment.subject===subjectFilter)).length}명</em></header>
        <div className="correction-slot-list">{slots.map(([start,end])=>{
          const inSlot=occurrences.filter(item=>item.date===date&&item.startTime.slice(0,5)===start);
          const fixedMoved=(data.assignments??[]).filter(item=>item.weekday===weekday&&item.startTime.slice(0,5)===start).map(item=>({item,exception:movedFrom.get(`${item.id}-${date}`)})).filter(row=>row.exception);
          const visibleInSlot=inSlot.filter(item=>subjectFilter==="전체"||item.assignment.subject===subjectFilter);
          const visibleFixedMoved=fixedMoved.filter(row=>subjectFilter==="전체"||row.item.subject===subjectFilter);
          const visibleEntries=[...visibleInSlot.map(row=>({key:row.key,assignment:row.assignment,state:row.state as Occurrence["state"]|"ghost"})),...visibleFixedMoved.map(row=>({key:`ghost-${row.item.id}`,assignment:row.item,state:"ghost" as const}))];
          const displayLimit=visibleEntries.length>8?7:8;
          const displayEntries=visibleEntries.slice(0,displayLimit);
          const hiddenCount=visibleEntries.length-displayEntries.length;
          const hasAny=visibleEntries.length>0;
          const slotAssistants=assistantsBySlot.get(`${weekday}-${start}`)??[];
          return <article className="correction-slot correction-slot-clickable" key={start} role="button" tabIndex={0} aria-label={`${day}요일 ${start} 학생 추가`} onClick={()=>setEditor({weekday,slot:start})} onKeyDown={event=>{if(event.key==="Enter"||event.key===" "){event.preventDefault();setEditor({weekday,slot:start});}}}>
            <div className="correction-slot-time"><b>{start}</b><span>– {end}</span>{slotAssistants.length?<div className="correction-slot-assistants" aria-label={`담당 조교 ${slotAssistants.map(item=>item.assistantName).join(", ")}`}>{slotAssistants.map(item=><small key={item.assistantId}>{item.assistantName}</small>)}</div>:null}</div>
            <div className="correction-slot-content">
              {hasAny?<div className="correction-slot-roster"><header className="correction-slot-summary" onClick={event=>event.stopPropagation()}><span><b>{visibleEntries.length}명</b>{(["국어","영어","수학"] as Assignment["subject"][]).map(subject=>{const count=visibleEntries.filter(entry=>entry.assignment.subject===subject).length;return count?<small className={`subject-${subject}`} key={subject}>{subject} {count}</small>:null})}</span><button type="button" aria-label={`${day}요일 ${start} 학생 추가`} onClick={()=>setEditor({weekday,slot:start})}>＋</button></header><div className="correction-slot-students" onClick={event=>event.stopPropagation()}>{displayEntries.map(entry=><button key={entry.key} data-subject={entry.assignment.subject} className={`correction-student subject-${entry.assignment.subject} ${entry.state}`} onClick={event=>{event.stopPropagation();setAction({assignment:entry.assignment,date});}}><span><b>{entry.assignment.studentName}</b><small>{entry.assignment.grade||"-"}</small></span></button>)}{hiddenCount>0?<button type="button" className="correction-slot-more" onClick={()=>setSlotRoster({day,date,start,end,entries:visibleEntries})}>+{hiddenCount}명</button>:null}</div></div>:<p className={`correction-slot-empty ${subjectFilter==="전체"?"add-prompt":"filtered-empty"}`}>{subjectFilter==="전체"?"학생 추가":`${subjectFilter} 학생 없음`}</p>}
            </div>
          </article>;
        })}</div>
      </section>;
    })}</section>}
    {editor&&data?<AssignmentEditor row={editor.row} initialWeekday={editor.weekday} initialSlot={editor.slot} overrideDate={editor.overrideDate} data={data} supabase={supabase} onClose={()=>setEditor(null)} onSaved={async()=>{setEditor(null);await load();}}/>:null}
    {action&&data?<ScheduleActionModal assignment={action.assignment} originalDate={action.date} supabase={supabase} onEdit={()=>{setEditor({row:action.assignment});setAction(null);}} onClose={()=>setAction(null)} onSaved={async()=>{setAction(null);await load();}}/>:null}
    {slotRoster?<SlotRosterModal value={slotRoster} onClose={()=>setSlotRoster(null)} onSelect={assignment=>{setSlotRoster(null);setAction({assignment,date:slotRoster.date})}}/>:null}
    {assistantEditorOpen&&assistantData?<AssistantScheduleEditor value={assistantData} supabase={supabase} onClose={()=>setAssistantEditorOpen(false)} onSaved={async()=>{setAssistantEditorOpen(false);await load();}}/>:null}
  </>;
}

export function CorrectionDateAssignmentEditor({date,supabase,onClose,onSaved}:{date:string;supabase:SupabaseClient;onClose:()=>void;onSaved:()=>Promise<void>}){
  const[data,setData]=useState<Board|null>(null);
  const[error,setError]=useState("");
  useEffect(()=>{void(async()=>{const{data:next,error:loadError}=await supabase.rpc("correction_management_board_v2",{p_anchor:date});if(loadError)setError(loadError.message);else setData(next as Board)})()},[date,supabase]);
  if(error)return <div className="modal-backdrop"><section className="student-modal correction-editor"><header><div><p className="eyebrow">과거 기록 보정</p><h2>이 날짜 누락 학생</h2></div><button type="button" onClick={onClose}>×</button></header><p className="form-error">{error}</p></section></div>;
  if(!data)return <div className="modal-backdrop"><section className="student-modal correction-editor"><p className="settings-empty">학생 명단을 불러오는 중이에요…</p></section></div>;
  return <AssignmentEditor initialWeekday={isoWeekday(date)} overrideDate={date} data={data} supabase={supabase} onClose={onClose} onSaved={onSaved}/>;
}

function SlotRosterModal({value,onClose,onSelect}:{value:NonNullable<SlotRosterState>;onClose:()=>void;onSelect:(assignment:Assignment)=>void}){
  return <div className="modal-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}><section className="student-modal correction-slot-roster-modal"><header><div><p className="eyebrow">첨삭 시간 전체 명단</p><h2>{value.day}요일 {value.start}–{value.end}</h2><span>학생을 누르면 이번 주 일정 변경·취소 메뉴를 열 수 있습니다.</span></div><button type="button" onClick={onClose}>×</button></header><div className="correction-slot-roster-groups">{(["국어","영어","수학"] as Assignment["subject"][]).map(subject=>{const entries=value.entries.filter(entry=>entry.assignment.subject===subject);if(!entries.length)return null;return <section className={`subject-${subject}`} key={subject}><header><b>{subject}</b><span>{entries.length}명</span></header><div>{entries.map(entry=><button type="button" key={entry.key} onClick={()=>onSelect(entry.assignment)}><b>{entry.assignment.studentName}</b><small>{[entry.assignment.school,entry.assignment.grade].filter(Boolean).join(" · ")||"학생 정보 없음"}</small></button>)}</div></section>})}</div><footer><button type="button" className="primary" onClick={onClose}>확인</button></footer></section></div>;
}

function AssistantScheduleEditor({value,supabase,onClose,onSaved}:{value:AssistantBoard;supabase:SupabaseClient;onClose:()=>void;onSaved:()=>Promise<void>}){
  const initial=useMemo(()=>new Set(value.assignments.map(item=>`${item.weekday}-${item.startTime.slice(0,5)}-${item.assistantId}`)),[value.assignments]);
  const[selected,setSelected]=useState(initial);
  const[mobileDay,setMobileDay]=useState(1);
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const toggle=(weekday:number,start:string,assistantId:string)=>setSelected(current=>{const next=new Set(current);const key=`${weekday}-${start}-${assistantId}`;if(next.has(key))next.delete(key);else next.add(key);return next;});
  const submit=async()=>{
    setSaving(true);setError("");
    const assignments:Array<{weekday:number;startTime:string;assistantId:string}>=[];
    for(let weekday=1;weekday<=7;weekday++){const slots=weekday<=5?weekdaySlots:weekendSlots;for(const[start]of slots){for(const assistant of value.assistants){if(selected.has(`${weekday}-${start}-${assistant.id}`))assignments.push({weekday,startTime:start,assistantId:assistant.id});}}}
    const{error:saveError}=await supabase.rpc("staff_save_correction_slot_assistants",{p_assignments:assignments});
    if(saveError){setError(saveError.message);setSaving(false);return;}
    await onSaved();
  };
  return <div className="modal-backdrop correction-assistant-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget&&!saving)onClose();}}><section className="student-modal correction-assistant-editor"><header><div><p className="eyebrow">매주 반복 담당표</p><h2>시간대별 담당 조교</h2><span>각 시간대에 근무하는 조교를 모두 선택해 주세요. 관리자와 선생님이 수정할 수 있습니다.</span></div><button type="button" onClick={onClose} disabled={saving}>×</button></header>{value.assistants.length?<><nav className="correction-assistant-mobile-days">{days.map((day,index)=><button type="button" key={day} className={mobileDay===index+1?"active":""} onClick={()=>setMobileDay(index+1)}>{day}</button>)}</nav><div className="correction-assistant-grid">{days.map((day,index)=>{const weekday=index+1;const slots=weekday<=5?weekdaySlots:weekendSlots;return <section key={day} className={mobileDay===weekday?"mobile-active":""}><h3>{day}요일</h3>{slots.map(([start,end])=><div className="correction-assistant-row" key={start}><time>{start}–{end}</time><div>{value.assistants.map(assistant=>{const active=selected.has(`${weekday}-${start}-${assistant.id}`);return <button type="button" key={assistant.id} className={active?"active":""} aria-pressed={active} onClick={()=>toggle(weekday,start,assistant.id)}>{active?<i>✓</i>:null}{assistant.name}</button>})}</div></div>)}</section>})}</div></>:<p className="correction-assistant-empty">활성 상태인 조교 계정이 없습니다. 먼저 계정 관리에서 조교 계정을 등록해 주세요.</p>}{error?<p className="form-error">{error}</p>:null}<footer><button type="button" className="secondary-button" disabled={saving} onClick={onClose}>취소</button><button type="button" className="primary" disabled={saving||!value.assistants.length} onClick={()=>void submit()}>{saving?"저장 중…":"담당표 저장"}</button></footer></section></div>;
}

function AssignmentEditor({row,initialWeekday,initialSlot,overrideDate,data,supabase,onClose,onSaved}:{row?:Assignment;initialWeekday?:number;initialSlot?:string;overrideDate?:string;data:Board;supabase:SupabaseClient;onClose:()=>void;onSaved:()=>Promise<void>}){
  const initialStudentId=row?.studentId??"";
  const[studentId,setStudentId]=useState(initialStudentId);
  const[studentQuery,setStudentQuery]=useState(()=>{
    const selected=data.students.find(item=>item.id===initialStudentId);
    return selected?`${selected.name} · ${[selected.school,selected.grade].filter(Boolean).join(" ")}`:"";
  });
  const[studentPickerOpen,setStudentPickerOpen]=useState(false);
  const visibleStudents=useMemo(()=>{
    const query=studentQuery.trim().toLowerCase();
    if(!query)return data.students.slice(0,8);
    return data.students.filter(item=>[item.name,item.school,item.grade].filter(Boolean).join(" ").toLowerCase().includes(query)).slice(0,8);
  },[data.students,studentQuery]);
  const chooseStudent=(item:Student)=>{
    setStudentId(item.id);
    setStudentQuery(`${item.name} · ${[item.school,item.grade].filter(Boolean).join(" ")}`);
    setStudentPickerOpen(false);
  };
  const[subject,setSubject]=useState<"국어"|"영어"|"수학">(row?.subject??"영어");
  const[weekday,setWeekday]=useState(row?.weekday??initialWeekday??1);
  const initial=findSlot(row?.weekday??initialWeekday??1,row?.startTime?.slice(0,5)??initialSlot);
  const[slot,setSlot]=useState<string>(initial);
  const[tutorId,setTutorId]=useState(row?.tutorId??"");
  const[supervisorId,setSupervisorId]=useState(row?.supervisorId??"");
  const[note,setNote]=useState(row?.note??"");
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const[deleteConfirmOpen,setDeleteConfirmOpen]=useState(false);
  const slots=weekday<=5?weekdaySlots:weekendSlots;

  useEffect(()=>{if(!slots.some(item=>item[0]===slot))setSlot(slots[0][0]);},[slot,slots]);

  const submit=async(event:FormEvent)=>{
    event.preventDefault();setSaving(true);setError("");
    const picked=slots.find(item=>item[0]===slot)??slots[0];
    const{error:saveError}=overrideDate
      ?await supabase.rpc("staff_add_correction_date_assignment",{p_date:overrideDate,p_student_id:studentId,p_subject:subject,p_start_time:picked[0],p_end_time:picked[1],p_tutor_profile_id:tutorId||null,p_supervisor_profile_id:supervisorId||null,p_note:note||null})
      :await supabase.rpc("staff_save_correction_assignment",{p_id:row?.id??null,p_student_id:studentId,p_subject:subject,p_weekday:weekday,p_start_time:picked[0],p_end_time:picked[1],p_tutor_profile_id:tutorId||null,p_supervisor_profile_id:supervisorId||null,p_note:note||null});
    if(saveError){setError(saveError.message.includes("duplicate")?"이미 같은 학생의 같은 과목 첨삭이 이 시간에 배정되어 있습니다.":saveError.message);setSaving(false);}else{
      window.dispatchEvent(new Event("hansalmae-correction-assignments-changed"));
      await onSaved();
    }
  };
  const remove=async()=>{
    if(!row)return;
    setSaving(true);
    const{error:removeError}=await supabase.rpc("staff_delete_correction_assignment",{p_id:row.id});
    if(removeError){setError(removeError.message);setSaving(false);setDeleteConfirmOpen(false);}else{
      window.dispatchEvent(new Event("hansalmae-correction-assignments-changed"));
      await onSaved();
    }
  };

  return <><div className="modal-backdrop"><section className="student-modal correction-editor"><header><div><p className="eyebrow">고정 첨삭 일정</p><h2>{row?"첨삭 배정 수정":"학생 첨삭 배정"}</h2><span>{row?"기본 일정은 매주 반복됩니다. 특정 주 변경은 별도 예외 일정으로 처리합니다.":`${days[weekday-1]}요일 ${slot} 시간에 학생을 추가합니다.`}</span></div><button onClick={onClose}>×</button></header><form onSubmit={submit}><div className="form-grid"><label className="correction-student-search-field">학생<div className="correction-student-picker"><input required value={studentQuery} autoComplete="off" placeholder="학생 이름·학교·학년 검색" onFocus={e=>{e.currentTarget.select();setStudentPickerOpen(true)}} onBlur={()=>window.setTimeout(()=>setStudentPickerOpen(false),120)} onChange={e=>{setStudentQuery(e.target.value);setStudentId("");setStudentPickerOpen(true)}} />{studentPickerOpen?<div className="correction-student-search-results">{visibleStudents.length?visibleStudents.map(item=><button type="button" key={item.id} className={studentId===item.id?"selected":""} onMouseDown={e=>e.preventDefault()} onClick={()=>chooseStudent(item)}><b>{item.name}</b><small>{[item.school,item.grade].filter(Boolean).join(" · ")||"학교·학년 미등록"}</small></button>):<p>검색 결과가 없습니다.</p>}</div>:null}</div></label><label>첨삭 과목<select value={subject} onChange={e=>setSubject(e.target.value as "국어"|"영어"|"수학")}><option>국어</option><option>영어</option><option>수학</option></select></label><label>요일<select value={weekday} onChange={e=>setWeekday(Number(e.target.value))}>{days.map((day,index)=><option key={day} value={index+1}>{day}요일</option>)}</select></label><label>시간<select value={slot} onChange={e=>setSlot(e.target.value)}>{slots.map(([start,end])=><option value={start} key={start}>{start}–{end}</option>)}</select></label><label>첨삭 담당<select value={tutorId} onChange={e=>setTutorId(e.target.value)}><option value="">미정</option>{data.staff.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>감독 선생님<select value={supervisorId} onChange={e=>setSupervisorId(e.target.value)}><option value="">미정</option>{data.staff.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="full">특이사항<input value={note} onChange={e=>setNote(e.target.value)} placeholder="예: 주간 테스트 · 내신 과제 확인"/></label></div>{error&&<p className="form-error">{error}</p>}<footer>{row?<button type="button" className="danger-link" disabled={saving} onClick={()=>setDeleteConfirmOpen(true)}>고정 배정 삭제</button>:<span/>}<span><button type="button" className="secondary-button" disabled={saving} onClick={onClose}>취소</button><button className="primary" disabled={saving||!studentId}>{saving?"저장 중…":"저장"}</button></span></footer></form></section></div>{row&&deleteConfirmOpen?<div className={confirmStyles.backdrop} onMouseDown={event=>{if(event.target===event.currentTarget&&!saving)setDeleteConfirmOpen(false)}}><section className={`${confirmStyles.dialog} ${confirmStyles.danger}`} role="alertdialog" aria-modal="true" aria-labelledby="correction-delete-confirm-title"><button type="button" className={confirmStyles.close} aria-label="삭제 확인창 닫기" disabled={saving} onClick={()=>setDeleteConfirmOpen(false)}>×</button><div className={confirmStyles.icon} aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M5 7h14M9 7V4.5h6V7m-8 0 1 13h8l1-13M10 10.5v6M14 10.5v6"/></svg></div><p className={confirmStyles.eyebrow}>고정 첨삭 배정 삭제</p><h3 id="correction-delete-confirm-title">{row.studentName} 학생 배정을 삭제할까요?</h3><p className={confirmStyles.copy}>{row.subject} · {days[row.weekday-1]}요일 {row.startTime.slice(0,5)}–{row.endTime.slice(0,5)} 고정 일정을 삭제합니다.</p><div className={confirmStyles.notice}><i aria-hidden="true">i</i><span>매주 반복되는 고정 배정에서 제외됩니다.</span></div><footer><button type="button" className={confirmStyles.cancel} disabled={saving} onClick={()=>setDeleteConfirmOpen(false)}>돌아가기</button><button type="button" className={confirmStyles.primary} disabled={saving} onClick={()=>void remove()}>{saving?"삭제 중…":"배정 삭제"}</button></footer></section></div>:null}</>;
}

function ScheduleActionModal({assignment,originalDate,supabase,onEdit,onClose,onSaved}:{assignment:Assignment;originalDate:string;supabase:SupabaseClient;onEdit:()=>void;onClose:()=>void;onSaved:()=>Promise<void>}){
  const[mode,setMode]=useState<"move"|"cancel"|"extra">("move");
  const[targetDate,setTargetDate]=useState(originalDate);
  const[targetStart,setTargetStart]=useState(assignment.startTime.slice(0,5));
  const[note,setNote]=useState("");
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const weekday=isoWeekday(targetDate);
  const slots=weekday<=5?weekdaySlots:weekendSlots;
  const picked=slots.find(item=>item[0]===targetStart)??slots[0];
  useEffect(()=>{if(!slots.some(item=>item[0]===targetStart))setTargetStart(slots[0][0]);},[slots,targetStart]);
  const submit=async()=>{setSaving(true);setError("");const{error:saveError}=await supabase.rpc("staff_save_correction_exception",{p_id:null,p_assignment_id:assignment.id,p_original_date:originalDate,p_kind:mode,p_target_date:mode==="cancel"?null:targetDate,p_target_start_time:mode==="cancel"?null:picked[0],p_target_end_time:mode==="cancel"?null:picked[1],p_note:note||null});if(saveError){setError(saveError.message.includes("duplicate")?"이 학생은 이번 주에 이미 변경 또는 취소 처리가 되어 있습니다.":saveError.message);setSaving(false);}else await onSaved();};
  return <div className="modal-backdrop"><section className="student-modal correction-action"><header><div><p className="eyebrow">이번 주만 변경</p><h2>{assignment.studentName} · {assignment.subject} 첨삭</h2><span>고정 일정 {days[assignment.weekday-1]} {assignment.startTime.slice(0,5)}–{assignment.endTime.slice(0,5)}은 그대로 유지됩니다.</span></div><button onClick={onClose}>×</button></header><div className="correction-action-types"><button className={mode==="move"?"active":""} onClick={()=>setMode("move")}>이번 주 시간 변경</button><button className={mode==="cancel"?"active":""} onClick={()=>setMode("cancel")}>이번 주 취소</button><button className={mode==="extra"?"active":""} onClick={()=>setMode("extra")}>추가 첨삭</button></div>{mode!=="cancel"&&<div className="form-grid correction-action-fields"><label>{mode==="move"?"변경 날짜":"추가 날짜"}<input type="date" value={targetDate} onChange={e=>setTargetDate(e.target.value)}/></label><label>시간<select value={targetStart} onChange={e=>setTargetStart(e.target.value)}>{slots.map(([start,end])=><option key={start} value={start}>{start}–{end}</option>)}</select></label></div>}<label className="correction-action-note">사유·메모<input value={note} onChange={e=>setNote(e.target.value)} placeholder="예: 병원 일정으로 수요일로 변경"/></label>{error&&<p className="form-error">{error}</p>}<footer><button className="secondary-button" onClick={onEdit}>고정 일정 수정</button><span><button className="secondary-button" onClick={onClose}>닫기</button><button className="primary" disabled={saving} onClick={()=>void submit()}>{saving?"저장 중…":"저장"}</button></span></footer></section></div>;
}

function buildOccurrences(data:Board|null):Occurrence[]{if(!data)return[];const weekEnd=addDays(data.weekStart,6);return (data.assignments??[]).flatMap(a=>{if(a.isDateOverride)return[];const date=addDays(data.weekStart,a.weekday-1);return isAssignmentVisibleInWeek(a,date,weekEnd)?[{key:`fixed-${a.id}-${date}`,assignment:a,date,startTime:a.startTime,endTime:a.endTime,state:"fixed" as const}]:[]})}
function isAssignmentVisibleInWeek(assignment:Assignment,date:string,weekEnd:string){
  if(assignment.validUntil)return assignment.validFrom<=date&&assignment.validUntil>=date;
  return assignment.validFrom<=weekEnd;
}
function findSlot(weekday:number,start?:string){const slots=weekday<=5?weekdaySlots:weekendSlots;return slots.find(item=>item[0]===start)?.[0]??slots[0][0]}
function addDays(value:string,delta:number){const d=new Date(`${value}T12:00:00+09:00`);d.setUTCDate(d.getUTCDate()+delta);return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(d)}
function isoWeekday(value:string){const d=new Date(`${value}T12:00:00+09:00`);const day=d.getUTCDay();return day===0?7:day}
function koreaToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function formatShortDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric"}).format(new Date(`${value}T12:00:00+09:00`))}
function formatWeek(value:string){return `${formatShortDate(value)} – ${formatShortDate(addDays(value,6))}`}
function formatDayTime(date?:string|null,time?:string|null){if(!date)return"변경";return `${days[isoWeekday(date)-1]} ${time?.slice(0,5)??""}`}
