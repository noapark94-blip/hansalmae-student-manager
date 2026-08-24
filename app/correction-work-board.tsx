"use client";

import { useCallback,useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { CorrectionMonthCalendar } from "./correction-month-calendar";
import { CorrectionHistoryModal } from "./correction-history-modal";

type Assignment={id:string;studentId:string;studentName:string;school:string|null;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string;tutorName:string|null;supervisorName:string|null;note:string|null};
type Exception={id:string;assignmentId:string;originalDate:string;kind:"move"|"cancel"|"extra";targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null;note:string|null};
type Board={assignments:Assignment[];exceptions:Exception[]};
type Occurrence={assignment:Assignment;date:string;startTime:string;endTime:string;kind:"fixed"|"move"|"extra";exception?:Exception};
type Report={id?:string;attendanceStatus?:string;lateMinutes?:number|null;absenceReason?:string;teacherInstruction?:string;examTitle?:string;examRange?:string;examScore?:number|null;examMaxScore?:number|null;evaluation?:string;homeworkInstruction?:string;homeworkStatus?:string|null;homeworkNote?:string;correctionContent?:string;assistantFeedback?:string;nextPreparation?:string;published?:boolean;recordedByName?:string|null};
type ExamCategory={id:string;name:string;isActive:boolean;sortOrder:number};
type AttendanceEditor={row:Occurrence;status:"late"|"absent";value:string};
type CorrectionReadStatus={reportAvailable:boolean;totalStudents:number;confirmedStudents:number;unconfirmedStudents:number;unlinkedStudents:number;students:{studentId:string;studentName:string;school:string|null;grade:string|null;status:"confirmed"|"unconfirmed"|"unlinked";viewedAt:string|null}[]};

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
  const[scheduleChangeRow,setScheduleChangeRow]=useState<Occurrence|null>(null);
  const[attendanceEditor,setAttendanceEditor]=useState<AttendanceEditor|null>(null);

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

  const persist=async(row:Occurrence,next:Report,publish:boolean)=>{
    const max=next.examMaxScore==null||Number(next.examMaxScore)<=0?100:Number(next.examMaxScore);
    const score=next.examScore==null?null:Number(next.examScore);
    if(score!==null&&(!Number.isFinite(score)||score<0||score>max))throw new Error(`${row.assignment.studentName} 학생의 시험 점수를 확인해 주세요.`);
    const{error:saveError}=await supabase.rpc("staff_save_correction_report_v2",{
      p_assignment_id:row.assignment.id,p_correction_date:row.date,p_start_time:row.startTime,p_end_time:row.endTime,
      p_attendance_status:next.attendanceStatus??"scheduled",p_late_minutes:next.attendanceStatus==="late"?(next.lateMinutes??null):null,
      p_absence_reason:next.attendanceStatus==="absent"?(next.absenceReason||null):null,
      p_teacher_instruction:next.teacherInstruction||null,p_exam_title:next.examTitle||null,p_exam_range:next.examRange||null,
      p_exam_score:score,p_exam_max_score:max,p_evaluation:next.evaluation||null,p_homework_instruction:next.homeworkInstruction||null,
      p_homework_status:next.homeworkStatus||null,p_homework_note:next.homeworkNote||null,p_correction_content:next.correctionContent||null,
      p_assistant_feedback:next.assistantFeedback||null,p_next_preparation:next.nextPreparation||null,p_published:publish
    });
    if(saveError)throw saveError;
    const refreshed=await supabase.rpc("staff_correction_report",{p_assignment_id:row.assignment.id,p_date:row.date,p_start_time:row.startTime});
    if(refreshed.error)updateDraft(row,{...next,published:publish,examMaxScore:max});
    else setDrafts(current=>({...current,[reportKey(row)]:(refreshed.data??{}) as Report}));
  };

  const saveAttendance=async(row:Occurrence,status:"present"|"late"|"absent")=>{
    const key=reportKey(row),current=drafts[key]??{};
    const nextStatus=current.attendanceStatus===status?"scheduled":status;
    if(nextStatus==="late"){setAttendanceEditor({row,status:"late",value:String(current.lateMinutes??10)});return}
    if(nextStatus==="absent"){setAttendanceEditor({row,status:"absent",value:current.absenceReason??""});return}
    setSaving(key);setError("");
    try{await persist(row,{...current,attendanceStatus:nextStatus,lateMinutes:null,absenceReason:""},false)}catch(e){setError(e instanceof Error?e.message:"출결을 저장하지 못했습니다.")}
    setSaving("");
  };

  const saveAttendanceDetail=async()=>{
    if(!attendanceEditor)return;
    const{row,status}=attendanceEditor,key=reportKey(attendanceEditor.row),current=drafts[reportKey(attendanceEditor.row)]??{};
    const value=attendanceEditor.value.trim();
    let late:number|null=null,reason="";
    if(status==="late"){late=Number(value);if(!Number.isFinite(late)||late<1){setError("지각 시간을 1분 이상의 숫자로 입력해 주세요.");return}}
    else{reason=value;if(!reason){setError("결석 사유를 입력해 주세요.");return}}
    setSaving(key);setError("");
    try{await persist(row,{...current,attendanceStatus:status,lateMinutes:late,absenceReason:reason},false);setAttendanceEditor(null)}
    catch(e){setError(e instanceof Error?e.message:"출결을 저장하지 못했습니다.")}
    setSaving("");
  };

  const saveAll=async(complete:boolean)=>{
    if(complete){const missing=rows.filter(row=>(drafts[reportKey(row)]?.attendanceStatus??"scheduled")==="scheduled").map(row=>row.assignment.studentName);if(missing.length){setError(`출결 미입력 학생: ${missing.join(", ")}`);return}}
    setSaving("all");setError("");
    try{for(const row of rows)await persist(row,drafts[reportKey(row)]??{},complete)}
    catch(e){setError(e instanceof Error?e.message:"첨삭 기록을 저장하지 못했습니다.");setSaving("");return}
    await load();setSaving("");
  };

  const renderRow=(row:Occurrence)=>{
    const key=reportKey(row),report=drafts[key]??{},status=report.attendanceStatus??"scheduled";
    const score=report.examScore,max=report.examMaxScore??100,converted=score==null||!Number.isFinite(Number(score))||!Number.isFinite(Number(max))||Number(max)<=0?null:Math.round(Number(score)/Number(max)*1000)/10;
    const originalLabel=row.kind==="move"&&row.exception?`${weekdays[isoWeekday(row.exception.originalDate)-1]} ${row.assignment.startTime.slice(0,5)} → ${weekdays[isoWeekday(row.date)-1]} ${row.startTime.slice(0,5)}`:row.kind==="extra"?"정규 일정 외 추가 첨삭":"";
    const changeReason=row.kind!=="fixed"?row.exception?.note?.trim()||"변경 사유 미입력":"";
    return <article key={key}>
      <div className="learning-person-attendance"><span className="learning-student"><button type="button" className="correction-history-trigger" title="과거 첨삭 기록 보기" onClick={()=>setHistoryStudent(row.assignment)}><i>{row.assignment.studentName[0]}</i><b>{row.assignment.studentName}</b><span className="correction-fixed-time">{weekdays[row.assignment.weekday-1]} {row.assignment.startTime.slice(0,5)}–{row.assignment.endTime.slice(0,5)}</span></button>{row.kind!=="fixed"?<span className={`correction-direct-badge ${row.kind}`}>{row.kind==="move"?"변경 일정":"추가 첨삭"}</span>:null}<small>{[row.assignment.school,row.assignment.grade,row.assignment.subject].filter(Boolean).join(" · ")}</small>{originalLabel?(row.kind==="move"?<button type="button" className="correction-direct-origin correction-direct-origin-button" title="변경 일정 확인·취소" onClick={()=>setScheduleChangeRow(row)}>{originalLabel}</button>:<small className="correction-direct-origin">{originalLabel}</small>):null}{changeReason?<span className="correction-change-reason"><b>{row.kind==="move"?"변경 사유":"추가 사유"}</b>{changeReason}</span>:null}{report.recordedByName?<small>첨삭 담당 · {report.recordedByName}</small>:null}</span><div className="learning-attendance">{attendance.map(([value,label])=><button type="button" key={value} className={`${value} ${status===value?"active":""}`} disabled={saving===key} onClick={()=>void saveAttendance(row,value)}>{label}</button>)}{status==="late"?<small>{report.lateMinutes}분 지각 · 같은 버튼을 다시 누르면 취소</small>:status==="absent"?<small>{report.absenceReason?`${report.absenceReason} · `:""}같은 버튼을 다시 누르면 취소</small>:status!=="scheduled"?<small>같은 버튼을 다시 누르면 취소</small>:null}</div></div>
      <div className="learning-exam-list"><div className="learning-exam-card"><div className="learning-exam individual correction-exam"><select value={report.examRange?.startsWith("[종류]")?report.examRange.slice(4).split("\n")[0]:""} onChange={e=>{const old=(report.examRange??"").replace(/^\[종류\].*\n?/,"");updateDraft(row,{examRange:e.target.value?`[종류]${e.target.value}\n${old}`:old})}}><option value="">종류 선택</option>{categories.map(category=><option key={category.id} value={category.name}>{category.name}</option>)}</select><input value={report.examTitle??""} onChange={e=>updateDraft(row,{examTitle:e.target.value})} placeholder="시험명·범위"/><span><input inputMode="decimal" value={report.examScore??""} onChange={e=>updateDraft(row,{examScore:e.target.value===""?null:Number(e.target.value)})} placeholder="원점수"/><em>/</em><input inputMode="decimal" value={report.examMaxScore??100} onChange={e=>updateDraft(row,{examMaxScore:e.target.value===""?null:Number(e.target.value)})} placeholder="만점"/></span><input value={report.evaluation??""} onChange={e=>updateDraft(row,{evaluation:e.target.value})} placeholder="평가·피드백"/></div><small className="exam-percent">{converted===null?"점수를 입력하면 100점 환산점수가 표시됩니다.":`원점수 ${score}/${max} · 환산 ${converted}점`}</small></div></div>
      <div className="correction-task-cell"><textarea value={report.correctionContent??""} onChange={e=>updateDraft(row,{correctionContent:e.target.value})} placeholder="오늘 실제로 진행한 첨삭 과제·오답·개념 설명 내용을 기록하세요." rows={5}/></div>
    </article>;
  };

  return <section className="class-learning-board correction-learning-board">
    <header><div><h3>이번 주 첨삭 기록</h3><p>출결·시험·오늘 한 첨삭과제를 한 화면에서 기록하고 학생·학부모 학습리포트와 성적 추이에 연결합니다.</p></div><div className="correction-learning-week-actions"><button type="button" className="secondary-button correction-calendar-button" onClick={()=>setMonthOpen(true)}>전체 첨삭 캘린더</button></div></header>
    <div className="class-week-navigation correction-week-navigation"><button type="button" aria-label="이전 주" onClick={()=>setDate(addDays(date,-7))}>‹</button><div className="class-week-strip correction-week-strip">{weekDates.map((day,index)=>{const dayRows=buildOccurrences(data,day);return <button key={day} className={`${day===date?"active":""} ${dayRows.length?"scheduled":""}`} aria-current={day===date?"date":undefined} onClick={()=>setDate(day)}><span>{weekdays[index]}</span><b>{+day.slice(8)}</b><small className="correction-mobile-day-count">{dayRows.length?`${dayRows.length}명`:"없음"}</small><div>{dayRows.slice(0,4).map(row=>{const report=drafts[reportKey(row)]??{};const status=report.attendanceStatus??"scheduled";return <em key={reportKey(row)} className={status==="scheduled"?"":status}>{row.assignment.studentName}{row.kind!=="fixed"?<span className={`correction-direct-badge compact ${row.kind}`}>{row.kind==="move"?"변경":"추가"}</span>:null}</em>})}{!dayRows.length?<small>첨삭 없음</small>:dayRows.every(row=>(drafts[reportKey(row)]?.attendanceStatus??"scheduled")==="scheduled")?<small>출석 전</small>:null}</div></button>})}</div><button type="button" aria-label="다음 주" onClick={()=>setDate(addDays(date,7))}>›</button></div>
    <CorrectionReportReadStatus key={`${date}-${Object.values(drafts).filter(report=>report.published).length}`} supabase={supabase} date={date}/>
    <div className="learning-board-heading correction-learning-heading"><span>학생·출결</span><span>시험 기록</span><span>오늘 한 첨삭과제</span></div>
    {loading?<p className="settings-empty">첨삭 기록을 불러오는 중이에요…</p>:<div className="learning-board-rows correction-learning-rows correction-subject-groups">{subjects.map(subject=>{const subjectRows=rows.filter(row=>row.assignment.subject===subject);if(!subjectRows.length)return null;return <section className={`correction-subject-group subject-${subject}`} key={subject}><header className="correction-subject-header"><div><b>{subject}</b><span>{subjectRows.length}명</span></div><small>{subject} 첨삭 학생</small></header><div className="correction-subject-rows">{subjectRows.map(renderRow)}</div></section>})}{!rows.length?<div className="makeup-empty"><p>이 날짜에 예정된 첨삭 학생이 없습니다.</p></div>:null}</div>}
    {error?<p className="form-error learning-board-error">{error}</p>:null}
    {rows.length?<footer><span>출결을 모두 입력하고 완료해야 누적 첨삭 횟수와 학생·학부모 리포트에 반영됩니다.</span><span className="learning-completion-actions"><button type="button" className="secondary-button" disabled={saving==="all"} onClick={()=>void saveAll(false)}>임시 저장</button><button type="button" className="primary" disabled={saving==="all"} onClick={()=>void saveAll(true)}>{saving==="all"?"저장 중…":"첨삭 완료"}</button></span></footer>:null}
    {monthOpen?<CorrectionMonthCalendar supabase={supabase} anchor={date} onSelect={setDate} onClose={()=>setMonthOpen(false)}/>:null}
    {historyStudent?<CorrectionHistoryModal supabase={supabase} student={historyStudent} onClose={()=>setHistoryStudent(null)}/>:null}
    {scheduleChangeRow?.exception?<CorrectionScheduleChangeModal row={scheduleChangeRow} supabase={supabase} onClose={()=>setScheduleChangeRow(null)} onReverted={async()=>{setScheduleChangeRow(null);await load();}}/>:null}
    {attendanceEditor?<div className="modal-backdrop nested attendance-editor-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)setAttendanceEditor(null)}}><form className="attendance-editor-modal" role="dialog" aria-modal="true" aria-labelledby="correction-attendance-editor-title" onSubmit={event=>{event.preventDefault();void saveAttendanceDetail()}}><header><span className={`attendance-editor-icon ${attendanceEditor.status}`}>{attendanceEditor.status==="late"?"분":"!"}</span><div><small>{attendanceEditor.status==="late"?"지각 시간 기록":"결석 사유 기록"}</small><h2 id="correction-attendance-editor-title">{attendanceEditor.row.assignment.studentName} 학생</h2></div><button type="button" aria-label="닫기" onClick={()=>setAttendanceEditor(null)}>×</button></header><label><b>{attendanceEditor.status==="late"?"몇 분 지각했나요?":"결석 사유를 입력해 주세요"}</b>{attendanceEditor.status==="late"?<div className="attendance-minute-input"><input autoFocus type="number" min="1" inputMode="numeric" value={attendanceEditor.value} onChange={event=>setAttendanceEditor(current=>current?{...current,value:event.target.value}:current)}/><span>분</span></div>:<textarea autoFocus rows={3} value={attendanceEditor.value} onChange={event=>setAttendanceEditor(current=>current?{...current,value:event.target.value}:current)} placeholder="예: 병원 진료, 개인 사정"/>}</label><footer><button type="button" className="secondary-button" onClick={()=>setAttendanceEditor(null)}>취소</button><button type="submit" className="primary" disabled={saving===reportKey(attendanceEditor.row)}>{saving===reportKey(attendanceEditor.row)?"저장 중…":"기록하기"}</button></footer></form></div>:null}
  </section>;
}

function CorrectionReportReadStatus({supabase,date}:{supabase:SupabaseClient;date:string}){
  const[data,setData]=useState<CorrectionReadStatus|null>(null);const[open,setOpen]=useState(false);const[loading,setLoading]=useState(true);const[available,setAvailable]=useState(true);
  const load=useCallback(async()=>{setLoading(true);const{data:next,error}=await supabase.rpc("staff_correction_report_read_status",{p_date:date});if(error){setAvailable(false);setData(null)}else{setAvailable(true);setData(next as CorrectionReadStatus)}setLoading(false)},[date,supabase]);
  useEffect(()=>{void load()},[load]);if(!available)return null;
  const confirmed=data?.confirmedStudents??0,unconfirmed=data?.unconfirmedStudents??0,unlinked=data?.unlinkedStudents??0;
  return <section className="family-read-status correction-read-status"><button type="button" className="family-read-summary" onClick={()=>setOpen(value=>!value)} disabled={loading}><span className="family-read-title"><small>첨삭 학부모 확인 현황</small><b>{!data?.reportAvailable?"리포트 생성 전":<>확인 <em>{confirmed}</em> / {data.totalStudents}명</>}</b></span><span className="family-read-pills">{data?.reportAvailable&&unconfirmed?<em className="unconfirmed">미확인 {unconfirmed}명</em>:null}{unlinked?<em className="unlinked">미연결 {unlinked}명</em>:null}<strong>{open?"접기":"학생별 보기 ›"}</strong></span></button>{open&&data?<div className="family-read-details">{data.students.map(student=><article key={student.studentId}><span><b>{student.studentName}</b><small>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생 정보"}</small></span><span className={`family-read-state ${student.status}`}>{student.status==="confirmed"?"학부모 확인":student.status==="unconfirmed"?"미확인":"학부모 계정 미연결"}{student.status==="confirmed"&&student.viewedAt?<small>{formatCorrectionReadTime(student.viewedAt)}</small>:null}</span></article>)}{!data.students.length?<p>완료된 첨삭 리포트가 없습니다.</p>:null}<footer><span>선택한 날짜에 완료된 첨삭 리포트의 확인 현황입니다.</span><button type="button" onClick={()=>void load()}>새로고침</button></footer></div>:null}</section>;
}

function CorrectionScheduleChangeModal({row,supabase,onClose,onReverted}:{row:Occurrence;supabase:SupabaseClient;onClose:()=>void;onReverted:()=>Promise<void>}){
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const exception=row.exception;
  if(!exception)return null;
  const original=`${weekdays[isoWeekday(exception.originalDate)-1]} ${row.assignment.startTime.slice(0,5)}–${row.assignment.endTime.slice(0,5)}`;
  const changed=`${weekdays[isoWeekday(row.date)-1]} ${row.startTime.slice(0,5)}–${row.endTime.slice(0,5)}`;
  const revert=async()=>{
    if(!confirm(`${row.assignment.studentName} 학생의 이번 주 일정 변경을 취소하고 ${original} 정규 일정으로 되돌릴까요?`))return;
    setSaving(true);setError("");
    const{error:removeError}=await supabase.rpc("staff_delete_correction_exception",{p_id:exception.id});
    if(removeError){setError(removeError.message);setSaving(false);return}
    await onReverted();
  };
  return <div className="modal-backdrop"><section className="student-modal correction-action correction-change-review"><header><div><p className="eyebrow">이번 주 변경 일정</p><h2>{row.assignment.studentName} · {row.assignment.subject} 첨삭</h2><span>정규 첨삭 시간표는 변경되지 않았습니다.</span></div><button type="button" onClick={onClose}>×</button></header><div className="correction-change-review-body"><p><b>정규 일정</b><span>{original}</span></p><p><b>변경 일정</b><span>{changed}</span></p><p><b>변경 사유</b><span>{exception.note?.trim()||"변경 사유 미입력"}</span></p></div>{error?<p className="form-error">{error}</p>:null}<footer><button type="button" className="danger-link" disabled={saving} onClick={()=>void revert()}>{saving?"취소 중…":"변경 취소"}</button><button type="button" className="secondary-button" disabled={saving} onClick={onClose}>닫기</button></footer></section></div>;
}

function reportKey(row:Occurrence){return `${row.assignment.id}-${row.date}-${row.startTime}`}
function buildOccurrences(data:Board|null,date:string):Occurrence[]{if(!data)return[];const weekday=isoWeekday(date);const rows:Occurrence[]=[];for(const a of data.assignments??[]){if(a.weekday===weekday){const x=(data.exceptions??[]).find(e=>e.assignmentId===a.id&&e.originalDate===date&&(e.kind==="move"||e.kind==="cancel"));if(!x)rows.push({assignment:a,date,startTime:a.startTime,endTime:a.endTime,kind:"fixed"})}}for(const x of data.exceptions??[]){if((x.kind==="move"||x.kind==="extra")&&x.targetDate===date&&x.targetStartTime&&x.targetEndTime){const a=(data.assignments??[]).find(v=>v.id===x.assignmentId);if(a)rows.push({assignment:a,date,startTime:x.targetStartTime,endTime:x.targetEndTime,kind:x.kind,exception:x})}}return rows.sort((a,b)=>a.startTime.localeCompare(b.startTime)||a.assignment.subject.localeCompare(b.assignment.subject,"ko")||a.assignment.studentName.localeCompare(b.assignment.studentName,"ko"))}
function isoWeekday(value:string){const d=new Date(`${value}T12:00:00+09:00`);const day=d.getUTCDay();return day===0?7:day}
function addDays(value:string,days:number){const d=new Date(`${value}T12:00:00+09:00`);d.setUTCDate(d.getUTCDate()+days);return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(d)}
function weekOf(value:string){const weekday=isoWeekday(value);const monday=addDays(value,1-weekday);return Array.from({length:7},(_,index)=>addDays(monday,index))}
function koreaToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function formatCorrectionReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
