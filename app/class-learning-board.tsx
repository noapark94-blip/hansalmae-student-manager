"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { StudentLearningHistory } from "./student-learning-history";

type Status="present"|"late"|"absent";
type Student={id:string;name:string;school:string|null;grade:string|null;status:Status|"excused"|null;lateMinutes:number|null;absenceReason:string|null;note:string|null};
type ExamDraft={id:string;examType:string;examTitle:string;score:string;maxScore:string;evaluation:string};
type Row=Omit<Student,"status">&{status:Status|null;lessonContent:string;exams:ExamDraft[];assignedHomework:string;previousHomework:string;inspectionStatus:string;inspectionNote:string};
type CalendarDay={date:string;scheduled:boolean;students:{id:string;name:string;status:Status|"excused"}[]};
type ExamResult={studentId:string;exams?:{id:string;examType:string|null;examTitle:string|null;score:number|null;maxScore:number|null;evaluation:string|null}[];id?:string;examType?:string|null;examTitle?:string|null;score?:number|null;maxScore?:number|null;evaluation?:string|null};
type HomeworkResult={studentId:string;lessonContent:string|null;assignedHomework:string|null;previousHomework:string|null;inspectionStatus:string|null;inspectionNote:string|null};
type ExamCategory={id:string;name:string;isActive:boolean;sortOrder:number};
type FamilyReadStudent={studentId:string;studentName:string;school:string|null;grade:string|null;guardianCount:number;readCount:number;status:"confirmed"|"unconfirmed"|"unlinked";viewedAt:string|null};
type FamilyReadStatus={lessonId:string|null;totalStudents:number;linkedStudents:number;confirmedStudents:number;unconfirmedStudents:number;unlinkedStudents:number;students:FamilyReadStudent[]};
type PreviousTemplate={lessonDate:string;lessonContent:string;notice:string;assignedHomework:string;exam:{examType?:string;examTitle?:string;maxScore?:number;evaluation?:string}};
type MakeupOption={id:string;name:string;school:string|null;grade:string|null;selected:boolean};
type AttendanceEditor={row:Row;status:"late"|"absent";value:string};

const attendance:[Status,string][]=[["present","출석"],["late","지각"],["absent","결석"]];
const homework=[["","미검사"],["complete","완료"],["partial","일부"],["missing","미제출"],["excused","면제"]];
const weekdays=["월","화","수","목","금","토","일"];
const emptyExam=():ExamDraft=>({id:"",examType:"",examTitle:"",score:"",maxScore:"100",evaluation:""});

export function ClassLearningBoard({supabase,classId,date,students,validDay,onDate,onReload}:{supabase:SupabaseClient;classId:string;date:string;students:Student[];validDay:boolean;onDate:(v:string)=>void;onReload:()=>Promise<void>}){
  const rootRef=useRef<HTMLElement|null>(null);
  const [rows,setRows]=useState<Row[]>([]);
  const [week,setWeek]=useState<CalendarDay[]>([]);
  const [notice,setNotice]=useState("");
  const [lessonContent,setLessonContent]=useState("");
  const [categories,setCategories]=useState<ExamCategory[]>([]);
  const [categoryOpen,setCategoryOpen]=useState(false);
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState("");
  const [error,setError]=useState("");
  const [monthOpen,setMonthOpen]=useState(false);
  const [historyStudent,setHistoryStudent]=useState<Row|null>(null);
  const [bulkOpen,setBulkOpen]=useState(false);
  const [noticeOpen,setNoticeOpen]=useState(false);
  const [commonHomework,setCommonHomework]=useState("");
  const [commonExamType,setCommonExamType]=useState("");
  const [commonExamTitle,setCommonExamTitle]=useState("");
  const [commonExamMax,setCommonExamMax]=useState("100");
  const [commonEvaluation,setCommonEvaluation]=useState("");
  const [templateLoading,setTemplateLoading]=useState(false);
  const [makeupOptions,setMakeupOptions]=useState<MakeupOption[]>([]);
  const [makeupLoading,setMakeupLoading]=useState(false);
  const [makeupEnabled,setMakeupEnabled]=useState(validDay);
  const [lessonState,setLessonState]=useState<"draft"|"completed">("draft");
  const [attendanceEditor,setAttendanceEditor]=useState<AttendanceEditor|null>(null);

  const loadWeek=useCallback(async()=>{const{data}=await supabase.rpc("staff_class_attendance_calendar",{p_class_id:classId,p_anchor_date:date,p_view:"week"});setWeek((data??[]) as CalendarDay[])},[classId,date,supabase]);
  const loadCategories=useCallback(async()=>{const{data,error:categoryError}=await supabase.rpc("staff_exam_categories");if(categoryError)setError(categoryError.message);else setCategories((data??[]) as ExamCategory[])},[supabase]);

  useEffect(()=>{let active=true;void supabase.rpc("staff_class_lesson_state",{p_class_id:classId,p_date:date}).then(({data})=>{if(active)setLessonState(data==="completed"?"completed":"draft")});return()=>{active=false}},[classId,date,supabase]);

  useEffect(()=>{
    const previous=rootRef.current?.previousElementSibling as HTMLElement|null;
    if(previous?.classList.contains("class-day-notice")) previous.style.display="none";
    return()=>{if(previous?.classList.contains("class-day-notice")) previous.style.display=""};
  },[]);

  useEffect(()=>{
    let active=true;
    if(validDay){setMakeupEnabled(true);setMakeupOptions([]);return()=>{active=false}};
    setMakeupLoading(true);
    void supabase.rpc("staff_class_makeup_options",{p_class_id:classId,p_date:date}).then(({data,error:makeupError})=>{
      if(!active)return;
      if(makeupError){setError(makeupError.message);setMakeupOptions([]);setMakeupEnabled(false)}else{
        const options=((data??[]) as MakeupOption[]);
        setMakeupOptions(options);
        setMakeupEnabled(options.some(item=>item.selected));
      }
      setMakeupLoading(false);
    });
    return()=>{active=false};
  },[classId,date,supabase,validDay]);

  useEffect(()=>{
    let active=true;setLoading(true);
    void Promise.all([
      supabase.rpc("staff_class_exam_results",{p_class_id:classId,p_date:date}),
      supabase.rpc("staff_class_homework_results",{p_class_id:classId,p_date:date}),
      supabase.rpc("staff_class_attendance_calendar",{p_class_id:classId,p_anchor_date:date,p_view:"week"}),
      supabase.rpc("staff_class_daily_notice",{p_class_id:classId,p_date:date}),
      supabase.rpc("staff_exam_categories"),
      supabase.rpc("staff_class_lesson_content",{p_class_id:classId,p_date:date}),
    ]).then(([examResponse,homeworkResponse,weekResponse,noticeResponse,categoryResponse,lessonResponse])=>{
      if(!active)return;
      if(examResponse.error||homeworkResponse.error||weekResponse.error||noticeResponse.error||categoryResponse.error){setError("개인별 기록을 불러오지 못했습니다. DB 최신 적용 여부를 확인해 주세요.");setLoading(false);return}
      const examRows=(examResponse.data??[]) as ExamResult[];
      const examsByStudent=new Map(examRows.map(item=>[item.studentId,item]));
      const homeworkByStudent=new Map(((homeworkResponse.data??[]) as HomeworkResult[]).map(item=>[item.studentId,item]));
      setRows(students.map(student=>{
        const raw=examsByStudent.get(student.id);const exam=raw?.exams?.[0]??(raw?{id:raw.id??"",examType:raw.examType??"",examTitle:raw.examTitle??"",score:raw.score??null,maxScore:raw.maxScore??100,evaluation:raw.evaluation??""}:null);const hw=homeworkByStudent.get(student.id);
        return {...student,status:student.status==="excused"?"absent":student.status,lessonContent:hw?.lessonContent??"",exams:[exam?{id:exam.id??"",examType:exam.examType??"",examTitle:exam.examTitle??"",score:exam.score==null?"":String(exam.score),maxScore:String(exam.maxScore??100),evaluation:exam.evaluation??""}:emptyExam()],assignedHomework:hw?.assignedHomework??"",previousHomework:hw?.previousHomework??"",inspectionStatus:hw?.inspectionStatus??"",inspectionNote:hw?.inspectionNote??""};
      }));
      setCategories((categoryResponse.data??[]) as ExamCategory[]);setWeek((weekResponse.data??[]) as CalendarDay[]);setNotice(String(noticeResponse.data??""));
      if(!lessonResponse.error)setLessonContent(String(lessonResponse.data??""));
      setError("");setLoading(false);
    });
    return()=>{active=false};
  },[classId,date,students,supabase]);

  const activateMakeupDay=async()=>{
    if(validDay||makeupEnabled)return;
    const ids=makeupOptions.map(item=>item.id);
    if(!ids.length){setError("현재 등록된 수강생이 없어 보강 수업을 만들 수 없습니다.");return}
    if(!confirm(`${date}을(를) 이 클래스의 보강 수업일로 등록할까요?\n현재 수강생 ${ids.length}명이 이 날짜 수업 기록 대상에 추가됩니다.`))return;
    setMakeupLoading(true);setError("");
    const{error:saveError}=await supabase.rpc("staff_save_class_makeup_students",{p_class_id:classId,p_date:date,p_student_ids:ids});
    if(saveError){setError(saveError.message);setMakeupLoading(false);return}
    setMakeupOptions(current=>current.map(item=>({...item,selected:true})));
    setMakeupEnabled(true);
    await onReload();
    await loadWeek();
    setMakeupLoading(false);
  };

  const deactivateMakeupDay=async()=>{
    if(validDay||!makeupEnabled)return;
    if(!confirm(`${date} 보강 수업 기록을 해제할까요?\\n출결·수업내용·숙제·시험 등 실제 기록이 있으면 해제되지 않습니다.`))return;
    setMakeupLoading(true);setError("");
    const{error:clearError}=await supabase.rpc("staff_clear_empty_class_makeup_day",{p_class_id:classId,p_date:date});
    if(clearError){setError(clearError.message);setMakeupLoading(false);return}
    setMakeupOptions(current=>current.map(item=>({...item,selected:false})));
    setMakeupEnabled(false);
    await onReload();
    await loadWeek();
    setMakeupLoading(false);
  };

  const update=(id:string,patch:Partial<Row>)=>setRows(current=>current.map(row=>row.id===id?{...row,...patch}:row));
  const updateExam=(studentId:string,patch:Partial<ExamDraft>)=>setRows(current=>current.map(row=>row.id===studentId?{...row,exams:[{...row.exams[0],...patch}]}:row));
  const applyHomework=()=>{if(!commonHomework.trim())return;setRows(current=>current.map(row=>({...row,assignedHomework:commonHomework})));};
  const applyLessonContent=()=>{if(!lessonContent.trim())return;setRows(current=>current.map(row=>({...row,lessonContent})));};
  const applyExam=()=>{setRows(current=>current.map(row=>({...row,exams:[{...row.exams[0],examType:commonExamType,examTitle:commonExamTitle,maxScore:commonExamMax||"100",evaluation:commonEvaluation}]})));};
  const clearCommon=()=>{setCommonHomework("");setCommonExamType("");setCommonExamTitle("");setCommonExamMax("100");setCommonEvaluation("")};

  const loadPreviousTemplate=async()=>{
    setTemplateLoading(true);setError("");
    const{data,error:templateError}=await supabase.rpc("staff_class_previous_learning_template",{p_class_id:classId,p_date:date});
    if(templateError){setError("이전 수업 기록을 불러오지 못했습니다. 072 migration 적용 여부를 확인해 주세요.");setTemplateLoading(false);return}
    if(!data){setError("이전에 저장된 수업 기록이 없습니다.");setTemplateLoading(false);return}
    const template=data as PreviousTemplate;
    setLessonContent(template.lessonContent??"");setNotice(template.notice??"");setCommonHomework(template.assignedHomework??"");
    setCommonExamType(template.exam?.examType??"");setCommonExamTitle(template.exam?.examTitle??"");setCommonExamMax(String(template.exam?.maxScore??100));setCommonEvaluation(template.exam?.evaluation??"");
    if(template.assignedHomework)setRows(current=>current.map(row=>({...row,assignedHomework:template.assignedHomework})));
    if(template.exam)setRows(current=>current.map(row=>({...row,exams:[{...row.exams[0],examType:template.exam.examType??"",examTitle:template.exam.examTitle??"",maxScore:String(template.exam.maxScore??100),evaluation:template.exam.evaluation??"",score:""}]})));
    setTemplateLoading(false);
  };

  const saveAttendance=async(row:Row,status:Status)=>{
    if(!validDay&&!makeupEnabled){setError("먼저 이 날짜를 보강 수업일로 등록해 주세요.");return}
    setSaving(row.id);setError("");
    if(row.status===status){const{error:clearError}=await supabase.rpc("staff_clear_class_attendance",{p_class_id:classId,p_date:date,p_student_id:row.id});if(clearError)setError(clearError.message);else{update(row.id,{status:null,lateMinutes:null,absenceReason:null});setLessonState("draft");await supabase.rpc("staff_set_class_lesson_state",{p_class_id:classId,p_date:date,p_state:"draft"});await loadWeek()}setSaving("");return}
    let late:number|null=null,reason:string|null=null;
    if(status==="late"){setAttendanceEditor({row,status,value:String(row.lateMinutes??10)});setSaving("");return}
    if(status==="absent"){setAttendanceEditor({row,status,value:row.absenceReason??""});setSaving("");return}
    const{error:saveError}=await supabase.rpc("staff_save_class_attendance",{p_class_id:classId,p_date:date,p_student_id:row.id,p_status:status,p_late_minutes:late,p_absence_reason:reason,p_note:row.note});
    if(saveError)setError(saveError.message);else{update(row.id,{status,lateMinutes:late,absenceReason:reason});await loadWeek()}
    setSaving("");
  };

  const saveAttendanceDetail=async()=>{
    if(!attendanceEditor)return;
    const{row,status}=attendanceEditor;const value=attendanceEditor.value.trim();let late:number|null=null,reason:string|null=null;
    if(status==="late"){late=Number(value);if(!Number.isFinite(late)||late<1){setError("지각 시간을 1분 이상의 숫자로 입력해 주세요.");return}}
    else{reason=value;if(!reason){setError("결석 사유를 입력해 주세요.");return}}
    setSaving(row.id);setError("");
    const{error:saveError}=await supabase.rpc("staff_save_class_attendance",{p_class_id:classId,p_date:date,p_student_id:row.id,p_status:status,p_late_minutes:late,p_absence_reason:reason,p_note:row.note});
    if(saveError)setError(saveError.message);else{update(row.id,{status,lateMinutes:late,absenceReason:reason});setAttendanceEditor(null);await loadWeek()}
    setSaving("");
  };

  const save=async(complete:boolean)=>{
    if(!validDay&&!makeupEnabled){setError("먼저 이 날짜를 보강 수업일로 등록해 주세요.");return}
    if(complete){const missing=rows.filter(row=>!row.status).map(row=>row.name);if(missing.length){setError(`출결 미입력 학생: ${missing.join(", ")}`);return}}
    for(const row of rows){const exam=row.exams[0];const max=exam.maxScore.trim()===""?100:+exam.maxScore;if(exam.score!==""&&(!Number.isFinite(+exam.score)||!Number.isFinite(max)||max<=0||+exam.score<0||+exam.score>max)){setError(`${row.name} 학생의 점수와 만점을 확인해 주세요.`);return}}
    setSaving("all");setError("");
    const examPayload=rows.map(row=>({studentId:row.id,exams:[{...row.exams[0],id:row.exams[0].id||null,examType:row.exams[0].examType||null,examTitle:row.exams[0].examTitle.trim()||null,score:row.exams[0].score===""?null:+row.exams[0].score,maxScore:row.exams[0].maxScore.trim()===""?null:+row.exams[0].maxScore,evaluation:row.exams[0].evaluation.trim()||null}]}));
    const homeworkPayload=rows.map(row=>({studentId:row.id,lessonContent:row.lessonContent.trim()||null,assignedHomework:row.assignedHomework.trim()||null,inspectionStatus:row.inspectionStatus||null,inspectionNote:row.inspectionNote.trim()||null}));
    const [examResponse,homeworkResponse,noticeResponse,lessonResponse]=await Promise.all([
      supabase.rpc("staff_save_class_exam_results",{p_class_id:classId,p_date:date,p_results:examPayload}),
      supabase.rpc("staff_save_class_homework_results",{p_class_id:classId,p_date:date,p_results:homeworkPayload}),
      supabase.rpc("staff_save_class_daily_notice",{p_class_id:classId,p_date:date,p_content:notice}),
      supabase.rpc("staff_save_class_lesson_content",{p_class_id:classId,p_date:date,p_content:lessonContent}),
    ]);
    if(examResponse.error||homeworkResponse.error||noticeResponse.error||lessonResponse.error){setError(examResponse.error?.message??homeworkResponse.error?.message??noticeResponse.error?.message??lessonResponse.error?.message??"저장하지 못했습니다.");setSaving("");return}
    const{data:stateData,error:stateError}=await supabase.rpc("staff_set_class_lesson_state",{p_class_id:classId,p_date:date,p_state:complete?"completed":"draft"});
    if(stateError){setError(stateError.message);setSaving("");return}
    setLessonState(stateData==="completed"?"completed":"draft");
    await onReload();
    setSaving("");
  };

  return <section className="class-learning-board" ref={rootRef}>
    <header><div><h3>이번 주 수업 기록</h3><p>출결·수업내용·시험·숙제를 한 화면에서 기록하고 학부모 학습리포트로 연결합니다.</p></div><div className="learning-header-actions"><button className="secondary-button" onClick={()=>setMonthOpen(true)}>전체 출석 캘린더</button></div></header>
    <div className="class-week-navigation"><button type="button" aria-label="이전 주" onClick={()=>onDate(shiftIsoDate(date,-7))}>‹</button><div className="class-week-strip">{week.map((day,index)=><button key={day.date} className={`${day.date===date?"active":""} ${day.scheduled?"scheduled":""}`} onClick={()=>onDate(day.date)}><span>{weekdays[index]}</span><b>{+day.date.slice(8)}</b><div>{day.students.slice(0,4).map(student=><em className={student.status==="excused"?"absent":student.status} key={student.id}>{student.name}</em>)}{!day.students.length?<small>{day.scheduled?"출석 전":"수업 없음"}</small>:null}</div></button>)}</div><button type="button" aria-label="다음 주" onClick={()=>onDate(shiftIsoDate(date,7))}>›</button></div>

    {!validDay&&!makeupEnabled?<section className="learning-common-record" style={{marginBottom:16}}><div className="learning-common-title"><div><small>정규 수업일 아님</small><b>{date} 보강 수업 기록</b></div><button type="button" className="primary" disabled={makeupLoading} onClick={()=>void activateMakeupDay()}>{makeupLoading?"등록 중…":"+ 보강 수업 기록"}</button></div><p style={{margin:0,color:"#6b6570",fontSize:14,lineHeight:1.6}}>이 날짜는 정규 수업 요일이 아닙니다. 보강 수업으로 등록하면 현재 수강생을 대상으로 출결·수업내용·숙제·시험을 평소와 똑같이 기록할 수 있습니다.</p>{error?<p className="form-error learning-board-error">{error}</p>:null}</section>:<>
    {!validDay&&makeupEnabled?<section className="class-day-notice" style={{marginBottom:16,display:"flex",alignItems:"center",justifyContent:"space-between",gap:12}}><span>보강 수업일로 등록된 날짜입니다. 아래에서 평소 수업과 동일하게 기록할 수 있습니다.</span><button type="button" className="danger-button" disabled={makeupLoading} onClick={()=>void deactivateMakeupDay()}>{makeupLoading?"해제 중…":"보강 수업 해제"}</button></section>:null}
    <section className="learning-compact-common">
      <div className="learning-compact-heading"><span><small>반 공통 기록</small><b>빠른 공통 입력</b></span><span><button type="button" className="secondary-button" disabled={templateLoading} onClick={()=>void loadPreviousTemplate()}>{templateLoading?"불러오는 중…":"지난 수업 불러오기"}</button><button type="button" className="learning-text-button" onClick={clearCommon}>일괄입력 비우기</button></span></div>
      <div className="learning-compact-row"><b>공통 수업 내용</b><textarea value={lessonContent} onChange={e=>setLessonContent(e.target.value)} placeholder="오늘 진행한 교재·단원·핵심 수업 내용" rows={1}/><button type="button" className="learning-apply-button" onClick={applyLessonContent}>전체 적용</button></div>
      <div className="learning-compact-row"><b>공통 숙제</b><textarea value={commonHomework} onChange={e=>setCommonHomework(e.target.value)} placeholder="교재·페이지·문제 번호·제출일" rows={1}/><button type="button" className="learning-apply-button" onClick={applyHomework}>전체 적용</button></div>
      <div className={`learning-compact-disclosure ${bulkOpen?"open":""}`}><button type="button" className="learning-disclosure-button" onClick={()=>setBulkOpen(v=>!v)}><b>공통 시험</b><span>{commonExamTitle||commonExamType||"시험이 있을 때만 입력"}</span><strong>{bulkOpen?"접기":"＋ 입력"}</strong></button>{bulkOpen?<div className="learning-compact-exam"><select value={commonExamType} onChange={e=>setCommonExamType(e.target.value)}><option value="">시험 종류</option>{categories.map(c=><option value={c.name} key={c.id}>{c.name}</option>)}</select><input value={commonExamTitle} onChange={e=>setCommonExamTitle(e.target.value)} placeholder="시험명·범위"/><input value={commonExamMax} onChange={e=>setCommonExamMax(e.target.value)} inputMode="decimal" placeholder="만점"/><input value={commonEvaluation} onChange={e=>setCommonEvaluation(e.target.value)} placeholder="공통 평가·피드백"/><button type="button" className="learning-apply-button" onClick={applyExam}>전체 적용</button><small>시험 정보만 복사되며 점수는 학생별로 입력합니다.</small></div>:null}</div>
      <div className={`learning-compact-disclosure ${noticeOpen?"open":""}`}><button type="button" className="learning-disclosure-button" onClick={()=>setNoticeOpen(v=>!v)}><b>반 전체 공지</b><span>{notice||"공지사항이 있을 때만 입력"}</span><strong>{noticeOpen?"접기":"＋ 입력"}</strong></button>{noticeOpen?<textarea className="learning-notice-input" value={notice} onChange={e=>setNotice(e.target.value)} placeholder="준비물·일정·반 전체 안내" rows={2}/>:null}</div>
    </section>

    <FamilyReportReadStatus supabase={supabase} classId={classId} date={date}/>
    <div className="learning-board-heading"><span>학생·출결</span><span>개인별 수업 내용</span><span className="learning-exam-heading"><b>개인별 시험</b><button type="button" onClick={()=>setCategoryOpen(true)}>시험 카테고리 관리</button></span><span>지난 숙제 검사</span><span>오늘 내줄 숙제</span></div>
    {loading?<p className="settings-empty">불러오는 중이에요…</p>:<div className="learning-board-rows">{rows.map(row=>{const exam=row.exams[0],score=Number(exam.score),max=Number(exam.maxScore);const converted=exam.score!==""&&Number.isFinite(score)&&Number.isFinite(max)&&max>0?Math.round(score/max*1000)/10:null;return <article key={row.id}>
      <div className="learning-person-attendance"><span className="learning-student"><button type="button" className="learning-student-history-button" onClick={()=>setHistoryStudent(row)} title={`${row.name} 학생 누적 수업 기록 보기`}><i>{row.name[0]}</i><b>{row.name}</b><small>{[row.school,row.grade].filter(Boolean).join(" · ")}</small></button></span><div className="learning-attendance">{attendance.map(([status,label])=><button key={status} className={`${status} ${row.status===status?"active":""}`} disabled={saving===row.id} onClick={()=>void saveAttendance(row,status)}>{label}</button>)}{row.status==="late"?<small>{row.lateMinutes}분 지각 · 같은 버튼을 다시 누르면 취소</small>:null}{row.status==="absent"?<small>{row.absenceReason?`${row.absenceReason} · `:""}같은 버튼을 다시 누르면 취소</small>:null}{row.status==="present"?<small>같은 버튼을 다시 누르면 취소</small>:null}</div></div>
      <div className="learning-individual-content"><textarea value={row.lessonContent} onChange={e=>update(row.id,{lessonContent:e.target.value})} placeholder="이 학생의 교재·단원·진도" rows={4}/></div>
      <div className="learning-exam-list"><div className="learning-exam-card"><div className="learning-exam-card-actions"><b>개인별 시험</b></div><div className="learning-exam individual"><select value={exam.examType} onChange={e=>updateExam(row.id,{examType:e.target.value})}><option value="">종류 선택</option>{categories.map(category=><option value={category.name} key={category.id}>{category.name}</option>)}</select><input value={exam.examTitle} onChange={e=>updateExam(row.id,{examTitle:e.target.value})} placeholder="시험명·범위"/><span><input inputMode="decimal" value={exam.score} onChange={e=>updateExam(row.id,{score:e.target.value})} placeholder="원점수"/><em>/</em><input inputMode="decimal" value={exam.maxScore} onChange={e=>updateExam(row.id,{maxScore:e.target.value})} placeholder="만점"/></span><input value={exam.evaluation} onChange={e=>updateExam(row.id,{evaluation:e.target.value})} placeholder="평가·피드백"/></div><small className="exam-percent">{converted===null?"점수를 입력하면 100점 환산점수가 표시됩니다.":`원점수 ${exam.score}/${exam.maxScore} · 환산 ${converted}점`}</small></div></div>
      <div className="learning-homework previous"><p>{row.previousHomework||"지난 숙제 없음"}</p><select value={row.inspectionStatus} onChange={e=>update(row.id,{inspectionStatus:e.target.value})}>{homework.map(([value,label])=><option value={value} key={value}>{label}</option>)}</select><input value={row.inspectionNote} onChange={e=>update(row.id,{inspectionNote:e.target.value})} placeholder="검사 메모"/></div>
      <div className="learning-homework assigned"><textarea value={row.assignedHomework} onChange={e=>update(row.id,{assignedHomework:e.target.value})} placeholder="교재·페이지·문제 번호·제출일" rows={4}/></div>
    </article>})}{!rows.length?<div className="makeup-empty"><p>이 날짜에 등록된 수강생이 없습니다.</p></div>:null}</div>}
    {error?<p className="form-error learning-board-error">{error}</p>:null}
    <footer><span><b>{lessonState==="completed"?"수업 완료":"기록 중"}</b> · 완료 처리된 기록만 학생 누적 수업 횟수와 학부모 리포트에 반영됩니다.</span><span className="learning-completion-actions"><button type="button" className="secondary-button" disabled={saving==="all"||!rows.length} onClick={()=>{if(lessonState==="completed"&&!confirm("수업 완료 기록을 취소할까요?\n입력 내용은 남아 있고 학생 누적 기록과 학부모 리포트에서만 빠집니다."))return;void save(false)}}>저장내용 취소</button><button type="button" className="primary" disabled={saving==="all"||!rows.length} onClick={()=>void save(true)}>{saving==="all"?"저장 중…":"수업 완료"}</button></span></footer>
    </>}
    {monthOpen?<Month supabase={supabase} classId={classId} anchor={date} onDate={value=>{onDate(value);setMonthOpen(false)}} onClose={()=>setMonthOpen(false)}/>:null}
    {categoryOpen?<ExamCategoryModal supabase={supabase} categories={categories} onClose={()=>setCategoryOpen(false)} onChanged={loadCategories}/>:null}
    {attendanceEditor?<div className="modal-backdrop nested attendance-editor-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)setAttendanceEditor(null)}}><form className="attendance-editor-modal" role="dialog" aria-modal="true" aria-labelledby="attendance-editor-title" onSubmit={event=>{event.preventDefault();void saveAttendanceDetail()}}><header><span className={`attendance-editor-icon ${attendanceEditor.status}`}>{attendanceEditor.status==="late"?"분":"!"}</span><div><small>{attendanceEditor.status==="late"?"지각 시간 기록":"결석 사유 기록"}</small><h2 id="attendance-editor-title">{attendanceEditor.row.name} 학생</h2></div><button type="button" aria-label="닫기" onClick={()=>setAttendanceEditor(null)}>×</button></header><label><b>{attendanceEditor.status==="late"?"몇 분 지각했나요?":"결석 사유를 입력해 주세요"}</b>{attendanceEditor.status==="late"?<div className="attendance-minute-input"><input autoFocus type="number" min="1" inputMode="numeric" value={attendanceEditor.value} onChange={event=>setAttendanceEditor(current=>current?{...current,value:event.target.value}:current)}/><span>분</span></div>:<textarea autoFocus rows={3} value={attendanceEditor.value} onChange={event=>setAttendanceEditor(current=>current?{...current,value:event.target.value}:current)} placeholder="예: 병원 진료, 개인 사정"/>}</label><footer><button type="button" className="secondary-button" onClick={()=>setAttendanceEditor(null)}>취소</button><button type="submit" className="primary" disabled={saving===attendanceEditor.row.id}>{saving===attendanceEditor.row.id?"저장 중…":"기록하기"}</button></footer></form></div>:null}
    {historyStudent?<div className="modal-backdrop nested" onMouseDown={event=>{if(event.target===event.currentTarget)setHistoryStudent(null)}}><section className="student-modal student-learning-history-modal" role="dialog" aria-modal="true"><header><div><p className="eyebrow">교직원 전용 · 누적 수업 기록</p><h2>{historyStudent.name}<small className="history-type-label">클래스 수업 기록</small></h2><span>{[historyStudent.school,historyStudent.grade].filter(Boolean).join(" · ")||"학생 기록"}</span></div><button type="button" aria-label="닫기" onClick={()=>setHistoryStudent(null)}>×</button></header><StudentLearningHistory supabase={supabase} studentId={historyStudent.id}/></section></div>:null}
  </section>;
}

function FamilyReportReadStatus({supabase,classId,date}:{supabase:SupabaseClient;classId:string;date:string}){
  const[data,setData]=useState<FamilyReadStatus|null>(null);const[open,setOpen]=useState(false);const[loading,setLoading]=useState(true);const[available,setAvailable]=useState(true);
  const load=useCallback(async()=>{setLoading(true);const{data:next,error}=await supabase.rpc("staff_class_family_report_read_status",{p_class_id:classId,p_date:date});if(error){setAvailable(false);setData(null)}else{setAvailable(true);setData(next as FamilyReadStatus)}setLoading(false)},[classId,date,supabase]);
  useEffect(()=>{void load()},[load]);if(!available)return null;
  const confirmed=data?.confirmedStudents??0,unconfirmed=data?.unconfirmedStudents??0,unlinked=data?.unlinkedStudents??0;const oldUnconfirmed=!!data?.lessonId&&unconfirmed>0&&daysAgo(date)>=2;
  return <section className={`family-read-status ${oldUnconfirmed?"needs-attention":""}`}><button type="button" className="family-read-summary" onClick={()=>setOpen(v=>!v)} disabled={loading}><span><small>학부모 학습리포트</small><b>{!data?.lessonId?"리포트 생성 전":`확인 ${confirmed}명 · 미확인 ${unconfirmed}명`}</b>{oldUnconfirmed?<em className="family-read-warning">2일 이상 미확인 학생이 있습니다.</em>:null}</span><span className="family-read-pills">{data?.lessonId?<em className="confirmed">확인 {confirmed}</em>:null}{data?.lessonId&&unconfirmed?<em className="unconfirmed">미확인 {unconfirmed}</em>:null}{unlinked?<em className="unlinked">학부모 미연결 {unlinked}</em>:null}<strong>{open?"접기":"학생별 보기"}</strong></span></button>{open&&data?<div className="family-read-details">{data.students.map(student=><article key={student.studentId} className={oldUnconfirmed&&student.status==="unconfirmed"?"stale-unconfirmed":""}><span><b>{student.studentName}</b><small>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생 정보"}</small></span><span className={`family-read-state ${student.status}`}>{student.status==="confirmed"?"학부모 확인":student.status==="unconfirmed"?(oldUnconfirmed?"오래 미확인":"미확인"):"학부모 계정 미연결"}{student.status==="confirmed"&&student.viewedAt?<small>{formatReadTime(student.viewedAt)}</small>:null}</span></article>)}{!data.students.length?<p>이 날짜의 수강 학생이 없습니다.</p>:null}<footer><span>학부모 또는 보호자 계정 중 한 명이라도 확인하면 ‘학부모 확인’으로 표시됩니다.</span><button type="button" onClick={()=>void load()}>새로고침</button></footer></div>:null}</section>;
}

function ExamCategoryModal({supabase,categories,onClose,onChanged}:{supabase:SupabaseClient;categories:ExamCategory[];onClose:()=>void;onChanged:()=>Promise<void>}){
  const[name,setName]=useState("");const[saving,setSaving]=useState("");const[error,setError]=useState("");
  const add=async()=>{if(!name.trim())return;setSaving("new");const{error:addError}=await supabase.rpc("staff_add_exam_category",{p_name:name.trim()});if(addError)setError(addError.message);else{setName("");await onChanged()}setSaving("")};
  const rename=async(category:ExamCategory)=>{const value=prompt("시험 카테고리 이름",category.name);if(value===null||!value.trim())return;setSaving(category.id);const{error:changeError}=await supabase.rpc("staff_set_exam_category",{p_id:category.id,p_name:value.trim(),p_active:true});if(changeError)setError(changeError.message);else await onChanged();setSaving("")};
  const remove=async(category:ExamCategory)=>{if(!confirm(`‘${category.name}’ 카테고리를 영구 삭제할까요?\n과거 시험 기록은 그대로 보존됩니다.`))return;setSaving(category.id);const{error:deleteError}=await supabase.rpc("staff_set_exam_category",{p_id:category.id,p_name:category.name,p_active:false});if(deleteError)setError(deleteError.message);else await onChanged();setSaving("")};
  return <div className="modal-backdrop nested"><section className="student-modal exam-category-modal"><header><div><p className="eyebrow">개인 설정</p><h2>시험 카테고리 관리</h2><span>선생님별 시험 종류를 추가·이름 변경하거나 영구 삭제할 수 있습니다.</span></div><button onClick={onClose}>×</button></header><div className="exam-category-add"><input autoFocus value={name} onChange={e=>setName(e.target.value)} onKeyDown={e=>{if(e.key==="Enter")void add()}} placeholder="새 시험 카테고리"/><button className="primary" disabled={saving==="new"} onClick={()=>void add()}>추가</button></div><div className="exam-category-list">{categories.map(category=><article key={category.id}><b>{category.name}</b><span><button className="secondary-button" disabled={saving===category.id} onClick={()=>void rename(category)}>이름 변경</button><button className="danger-button" disabled={saving===category.id} onClick={()=>void remove(category)}>영구 삭제</button></span></article>)}</div>{error?<p className="form-error">{error}</p>:null}<footer><button className="primary" onClick={onClose}>완료</button></footer></section></div>;
}

function Month({supabase,classId,anchor,onDate,onClose}:{supabase:SupabaseClient;classId:string;anchor:string;onDate:(v:string)=>void;onClose:()=>void}){
  const[month,setMonth]=useState(anchor.slice(0,7));const[records,setRecords]=useState<Record<string,CalendarDay>>({});const[loading,setLoading]=useState(true);const[error,setError]=useState("");const calendar=classCalendarDays(month);
  useEffect(()=>{let active=true;const load=async()=>{setLoading(true);setError("");const months=Array.from(new Set(calendar.map(date=>date.slice(0,7))));const responses=await Promise.all(months.map(value=>supabase.rpc("staff_class_attendance_calendar",{p_class_id:classId,p_anchor_date:`${value}-01`,p_view:"month"})));if(!active)return;const failed=responses.find(response=>response.error);if(failed){setError("출석 캘린더를 불러오지 못했습니다.");setRecords({})}else{const next:Record<string,CalendarDay>={};for(const response of responses)for(const day of (response.data??[]) as CalendarDay[])next[day.date]=day;setRecords(next)}setLoading(false)};void load();return()=>{active=false}},[classId,month,supabase]);
  return <div className="modal-backdrop nested" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}><section className="student-modal class-month-modal correction-month-modal"><header><div><p className="eyebrow">전체 출결 현황</p><h2>전체 출석 캘린더</h2><span>월간 수업 예정과 출석·지각·결석 기록을 한눈에 확인합니다.</span></div><button type="button" onClick={onClose}>×</button></header><nav className="correction-month-toolbar" aria-label="출석 달력 월 이동"><button type="button" aria-label="이전 달" onClick={()=>setMonth(shiftMonth(month,-1))}>‹</button><strong>{formatMonth(month)}</strong><button type="button" aria-label="다음 달" onClick={()=>setMonth(shiftMonth(month,1))}>›</button><button type="button" onClick={()=>setMonth(koreaMonth())}>이번 달</button></nav>{error?<p className="form-error">{error}</p>:null}{loading?<p className="correction-month-loading">캘린더를 불러오는 중이에요…</p>:<><div className="correction-month-weekdays">{weekdays.map(day=><b key={day}>{day}</b>)}</div><div className="correction-month-grid">{calendar.map(date=>{const day=records[date],students=day?.students??[],inMonth=date.slice(0,7)===month;return <button type="button" key={date} className={`${inMonth?"":"outside"} ${date===anchor?"selected":""} ${date===koreaToday()?"today":""} ${day?.scheduled?"scheduled":""}`} onClick={()=>{onDate(date);onClose()}}><span>{+date.slice(8)}</span><div>{students.slice(0,4).map(student=><em className={student.status==="excused"?"absent":student.status} key={student.id}>{student.name}</em>)}{students.length>4?<small>+{students.length-4}명</small>:null}{!students.length?<small className="empty">{day?.scheduled?"출석 전":"수업 없음"}</small>:null}</div></button>})}</div></>}</section></div>;
}

function daysAgo(value:string){const target=new Date(`${value}T00:00:00+09:00`).getTime();return Math.floor((Date.now()-target)/86400000)}
function formatReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function isoWeekday(value:string){const day=new Date(`${value}T00:00:00`).getDay();return day===0?7:day}
function shiftIsoDate(value:string,days:number){const next=new Date(`${value}T00:00:00+09:00`);next.setDate(next.getDate()+days);return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(next)}
function shiftMonth(value:string,amount:number){const[year,month]=value.split("-").map(Number);const next=new Date(Date.UTC(year,month-1+amount,1));return `${next.getUTCFullYear()}-${String(next.getUTCMonth()+1).padStart(2,"0")}`}
function koreaMonth(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit"}).format(new Date())}
function formatMonth(value:string){const[year,month]=value.split("-");return `${year}년 ${Number(month)}월`}
function koreaToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function classCalendarDays(month:string){const first=`${month}-01`,start=shiftIsoDate(first,1-isoWeekday(first));const[yearValue,monthValue]=month.split("-").map(Number);const lastDate=new Date(Date.UTC(yearValue,monthValue,0));const last=`${lastDate.getUTCFullYear()}-${String(lastDate.getUTCMonth()+1).padStart(2,"0")}-${String(lastDate.getUTCDate()).padStart(2,"0")}`,end=shiftIsoDate(last,7-isoWeekday(last));const dates:string[]=[];for(let date=start;;date=shiftIsoDate(date,1)){dates.push(date);if(date===end)break}return dates}
