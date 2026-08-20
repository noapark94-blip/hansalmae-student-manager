"use client";

import { useCallback,useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CorrectionMonthCalendar } from "./correction-month-calendar";
import { CorrectionHistoryModal } from "./correction-history-modal";

type Assignment={id:string;studentId:string;studentName:string;school:string|null;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string;tutorName:string|null;supervisorName:string|null;note:string|null};
type Exception={id:string;assignmentId:string;originalDate:string;kind:"move"|"cancel"|"extra";targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null;note:string|null};
type Board={assignments:Assignment[];exceptions:Exception[]};
type Occurrence={assignment:Assignment;date:string;startTime:string;endTime:string;kind:"fixed"|"move"|"extra";exception?:Exception};
type Report={id?:string;attendanceStatus?:string;lateMinutes?:number|null;teacherInstruction?:string;examTitle?:string;examRange?:string;examScore?:number|null;examMaxScore?:number|null;evaluation?:string;homeworkInstruction?:string;homeworkStatus?:string|null;homeworkNote?:string;correctionContent?:string;assistantFeedback?:string;nextPreparation?:string;published?:boolean;recordedByName?:string|null};
type ExamCategory={id:string;name:string;isActive:boolean;sortOrder:number};

const weekdays=["월","화","수","목","금","토","일"];
const subjects:["국어","영어","수학"]=["국어","영어","수학"];
const attendance:[["present","출석"],["late","지각"],["absent","결석"]]=[["present","출석"],["late","지각"],["absent","결석"]];

export function CorrectionWorkBoard({supabase}:{supabase:SupabaseClient}){
  const[date,setDate]=useState(koreaToday());
  const[data,setData]=useState<Board|null>(null);
  const[drafts,setDrafts]=useState<Record<string,Report>>({});
  const[categories,setCategories]=useState<ExamCategory[]>([]);
  const[loading,setLoading]=useState(true);
  const[saving,setSaving]=useState("");
  const[error,setError]=useState("");
  const[monthOpen,setMonthOpen]=useState(false);
  const[historyStudent,setHistoryStudent]=useState<Assignment|null>(null);

  const weekDates=useMemo(()=>weekOf(date),[date]);
  const load=useCallback(async()=>{
    setLoading(true);setError("");
    const[boardResponse,categoryResponse]=await Promise.all([
      supabase.rpc("correction_management_board",{p_anchor:date}),
      supabase.rpc("staff_exam_categories")
    ]);
    if(boardResponse.error){setError("첨삭 진행 명단을 불러오지 못했습니다.");setData(null);setLoading(false);return}
    const board=boardResponse.data as Board;
    const dates=weekOf(date);
    const occurrences=dates.flatMap(day=>buildOccurrences(board,day));
    const reportRows=await Promise.all(occurrences.map(async row=>{
      const response=await supabase.rpc("staff_correction_report",{p_assignment_id:row.assignment.id,p_date:row.date,p_start_time:row.startTime});
      return [reportKey(row),(response.data??{}) as Report] as const;
    }));
    setData(board);
    setDrafts(Object.fromEntries(reportRows));
    if(!categoryResponse.error)setCategories((categoryResponse.data??[]) as ExamCategory[]);
    setLoading(false);
  },[date,supabase]);

  useEffect(()=>{void load()},[load]);
  const rows=useMemo(()=>buildOccurrences(data,date),[data,date]);
  const updateDraft=(row:Occurrence,patch:Partial<Report>)=>setDrafts(current=>({...current,[reportKey(row)]:{...(current[reportKey(row)]??{}),...patch}}));

  const persist=async(row:Occurrence,next:Report)=>{
    const max=next.examMaxScore==null||Number(next.examMaxScore)<=0?100:Number(next.examMaxScore);
    const score=next.examScore==null?null:Number(next.examScore);
    if(score!==null&&(!Number.isFinite(score)||score<0||score>max))throw new Error(`${row.assignment.studentName} 학생의 시험 점수를 확인해 주세요.`);
    const{error:saveError}=await supabase.rpc("staff_save_correction_report",{
      p_assignment_id:row.assignment.id,p_correction_date:row.date,p_start_time:row.startTime,p_end_time:row.endTime,
      p_attendance_status:next.attendanceStatus??"scheduled",p_late_minutes:next.attendanceStatus==="late"?(next.lateMinutes??null):null,
      p_teacher_instruction:next.teacherInstruction||null,p_exam_title:next.examTitle||null,p_exam_range:next.examRange||null,
      p_exam_score:score,p_exam_max_score:max,p_evaluation:next.evaluation||null,p_homework_instruction:next.homeworkInstruction||null,
      p_homework_status:next.homeworkStatus||null,p_homework_note:next.homeworkNote||null,p_correction_content:next.correctionContent||null,
      p_assistant_feedback:next.assistantFeedback||null,p_next_preparation:next.nextPreparation||null,p_published:true
    });
    if(saveError)throw saveError;
    const refreshed=await supabase.rpc("staff_correction_report",{p_assignment_id:row.assignment.id,p_date:row.date,p_start_time:row.startTime});
    if(refreshed.error)updateDraft(row,{...next,published:true,examMaxScore:max});
    else setDrafts(current=>({...current,[reportKey(row)]:(refreshed.data??{}) as Report}));
  };

  const saveAttendance=async(row:Occurrence,status:"present"|"late"|"absent")=>{
    const key=reportKey(row),current=drafts[key]??{};
    const nextStatus=current.attendanceStatus===status?"scheduled":status;
    let late:number|null=null;
    if(nextStatus==="late"){
      const value=prompt(`${row.assignment.studentName} 학생은 몇 분 지각했나요?`,String(current.lateMinutes??10));
      if(value===null)return;
      late=Number(value);if(!Number.isFinite(late)||late<1){setError("지각 시간을 숫자로 입력해 주세요.");return}
    }
    setSaving(key);setError("");
    try{await persist(row,{...current,attendanceStatus:nextStatus,lateMinutes:late})}catch(e){setError(e instanceof Error?e.message:"출결을 저장하지 못했습니다.")}
    setSaving("");
  };

  const saveAll=async()=>{
    setSaving("all");setError("");
    try{for(const row of rows)await persist(row,drafts[reportKey(row)]??{})}
    catch(e){setError(e instanceof Error?e.message:"첨삭 기록을 저장하지 못했습니다.");setSaving("");return}
    await load();setSaving("");
  };

  const renderRow=(row:Occurrence)=>{
    const key=reportKey(row),report=drafts[key]??{},status=report.attendanceStatus??"scheduled";
    const score=report.examScore,max=report.examMaxScore??100,converted=score==null||!Number.isFinite(Number(score))||!Number.isFinite(Number(max))||Number(max)<=0?null:Math.round(Number(score)/Number(max)*1000)/10;
    const originalLabel=row.kind==="move"&&row.exception?`기존 ${weekdays[isoWeekday(row.exception.originalDate)-1]} ${row.assignment.startTime.slice(0,5)} → ${weekdays[isoWeekday(row.date)-1]} ${row.startTime.slice(0,5)}`:row.kind==="extra"?"정규 일정 외 추가 첨삭":"";
    return <article key={key}>
      <div className="learning-person-attendance"><span className="learning-student"><button type="button" className="correction-history-trigger" title="과거 첨삭 기록 보기" onClick={()=>setHistoryStudent(row.assignment)}><i>{row.assignment.studentName[0]}</i><b>{row.assignment.studentName}</b></button>{row.kind!=="fixed"?<span className={`correction-direct-badge ${row.kind}`}>{row.kind==="move"?"변경 일정":"추가 첨삭"}</span>:null}<small>{[row.assignment.school,row.assignment.grade,row.assignment.subject].filter(Boolean).join(" · ")}</small>{originalLabel?<small className="correction-direct-origin">{originalLabel}</small>:null}{report.recordedByName?<small>첨삭 담당 · {report.recordedByName}</small>:null}</span><div className="learning-attendance">{attendance.map(([value,label])=><button type="button" key={value} className={`${value} ${status===value?"active":""}`} disabled={saving===key} onClick={()=>void saveAttendance(row,value)}>{label}</button>)}{status==="late"?<small>{report.lateMinutes}분 지각 · 같은 버튼을 다시 누르면 취소</small>:status!=="scheduled"?<small>같은 버튼을 다시 누르면 취소</small>:null}</div></div>
      <div className="learning-exam-list"><div className="learning-exam-card"><div className="learning-exam individual correction-exam"><select value={report.examRange?.startsWith("[종류]")?report.examRange.slice(4).split("\n")[0]:""} onChange={e=>{const old=(report.examRange??"").replace(/^\[종류\].*\n?/,"");updateDraft(row,{examRange:e.target.value?`[종류]${e.target.value}\n${old}`:old})}}><option value="">종류 선택</option>{categories.map(category=><option key={category.id} value={category.name}>{category.name}</option>)}</select><input value={report.examTitle??""} onChange={e=>updateDraft(row,{examTitle:e.target.value})} placeholder="시험명·범위"/><span><input inputMode="decimal" value={report.examScore??""} onChange={e=>updateDraft(row,{examScore:e.target.value===""?null:Number(e.target.value)})} placeholder="원점수"/><em>/</em><input inputMode="decimal" value={report.examMaxScore??100} onChange={e=>updateDraft(row,{examMaxScore:e.target.value===""?null:Number(e.target.value)})} placeholder="만점"/></span><input value={report.evaluation??""} onChange={e=>updateDraft(row,{evaluation:e.target.value})} placeholder="평가·피드백"/></div><small className="exam-percent">{converted===null?"점수를 입력하면 100점 환산점수가 표시됩니다.":`원점수 ${score}/${max} · 환산 ${converted}점`}</small></div></div>
      <div className="correction-task-cell"><textarea value={report.correctionContent??""} onChange={e=>updateDraft(row,{correctionContent:e.target.value})} placeholder="오늘 실제로 진행한 첨삭 과제·오답·개념 설명 내용을 기록하세요." rows={5}/></div>
    </article>;
  };

  return <section className="class-learning-board correction-learning-board">
    <header><div><h3>이번 주 첨삭 기록</h3><p>출결·시험·오늘 한 첨삭과제를 한 화면에서 기록하고 학생·학부모 학습리포트와 성적 추이에 연결합니다.</p></div><div className="correction-learning-week-actions"><button type="button" className="secondary-button correction-calendar-button" onClick={()=>setMonthOpen(true)}>전체 첨삭 캘린더</button><button type="button" className="secondary-button" onClick={()=>setDate(addDays(date,-7))}>‹ 이전 주</button><button type="button" className="secondary-button" onClick={()=>setDate(koreaToday())}>이번 주</button><button type="button" className="secondary-button" onClick={()=>setDate(addDays(date,7))}>다음 주 ›</button></div></header>
    <div className="class-week-strip correction-week-strip">{weekDates.map((day,index)=>{const dayRows=buildOccurrences(data,day);return <button key={day} className={`${day===date?"active":""} ${dayRows.length?"scheduled":""}`} onClick={()=>setDate(day)}><span>{weekdays[index]}</span><b>{+day.slice(8)}</b><div>{dayRows.slice(0,4).map(row=>{const report=drafts[reportKey(row)]??{};const status=report.attendanceStatus??"scheduled";return <em key={reportKey(row)} className={status==="scheduled"?"":status}>{row.assignment.studentName}{row.kind!=="fixed"?<span className={`correction-direct-badge compact ${row.kind}`}>{row.kind==="move"?"변경":"추가"}</span>:null}</em>})}{!dayRows.length?<small>첨삭 없음</small>:dayRows.every(row=>(drafts[reportKey(row)]?.attendanceStatus??"scheduled")==="scheduled")?<small>출석 전</small>:null}</div></button>})}</div>
    <div className="learning-board-heading correction-learning-heading"><span>학생·출결</span><span>시험 기록</span><span>오늘 한 첨삭과제</span></div>
    {loading?<p className="settings-empty">첨삭 기록을 불러오는 중이에요…</p>:<div className="learning-board-rows correction-learning-rows correction-subject-groups">{subjects.map(subject=>{const subjectRows=rows.filter(row=>row.assignment.subject===subject);if(!subjectRows.length)return null;return <section className={`correction-subject-group subject-${subject}`} key={subject}><header className="correction-subject-header"><div><b>{subject}</b><span>{subjectRows.length}명</span></div><small>{subject} 첨삭 학생</small></header><div className="correction-subject-rows">{subjectRows.map(renderRow)}</div></section>})}{!rows.length?<div className="makeup-empty"><p>이 날짜에 예정된 첨삭 학생이 없습니다.</p></div>:null}</div>}
    {error?<p className="form-error learning-board-error">{error}</p>:null}
    <footer><span>출결은 즉시 저장되고, 첨삭 기록 저장 시 학생·학부모 리포트와 첨삭시험 성적 추이에 바로 반영됩니다.</span><button type="button" className="primary" disabled={saving==="all"||!rows.length} onClick={()=>void saveAll()}>{saving==="all"?"저장 중…":"첨삭 기록 저장"}</button></footer>
    {monthOpen?<CorrectionMonthCalendar supabase={supabase} anchor={date} onSelect={setDate} onClose={()=>setMonthOpen(false)}/>:null}
    {historyStudent?<CorrectionHistoryModal supabase={supabase} student={historyStudent} onClose={()=>setHistoryStudent(null)}/>:null}
  </section>;
}

function reportKey(row:Occurrence){return `${row.assignment.id}-${row.date}-${row.startTime}`}
function buildOccurrences(data:Board|null,date:string):Occurrence[]{if(!data)return[];const weekday=isoWeekday(date);const rows:Occurrence[]=[];for(const a of data.assignments??[]){if(a.weekday===weekday){const x=(data.exceptions??[]).find(e=>e.assignmentId===a.id&&e.originalDate===date&&(e.kind==="move"||e.kind==="cancel"));if(!x)rows.push({assignment:a,date,startTime:a.startTime,endTime:a.endTime,kind:"fixed"})}}for(const x of data.exceptions??[]){if((x.kind==="move"||x.kind==="extra")&&x.targetDate===date&&x.targetStartTime&&x.targetEndTime){const a=(data.assignments??[]).find(v=>v.id===x.assignmentId);if(a)rows.push({assignment:a,date,startTime:x.targetStartTime,endTime:x.targetEndTime,kind:x.kind,exception:x})}}return rows.sort((a,b)=>a.startTime.localeCompare(b.startTime)||a.assignment.subject.localeCompare(b.assignment.subject,"ko")||a.assignment.studentName.localeCompare(b.assignment.studentName,"ko"))}
function isoWeekday(value:string){const d=new Date(`${value}T12:00:00+09:00`);const day=d.getUTCDay();return day===0?7:day}
function addDays(value:string,days:number){const d=new Date(`${value}T12:00:00+09:00`);d.setUTCDate(d.getUTCDate()+days);return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(d)}
function weekOf(value:string){const weekday=isoWeekday(value);const monday=addDays(value,1-weekday);return Array.from({length:7},(_,index)=>addDays(monday,index))}
function koreaToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}