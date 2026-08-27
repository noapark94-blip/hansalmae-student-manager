"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";
import { appConfirm } from "./app-dialog";

type AttendanceInfo={status:string;lateMinutes:number|null;absenceReason:string;note:string}|null;
type HomeworkResult={status:string;note:string}|null;
type Exam={id:string;examType:string;examTitle:string;score:number|null;maxScore:number;percent:number|null;evaluation:string;feedback:string};
type Report={lessonId:string;lessonDate:string;startsAt:string;classId:string;className:string;subject:string;room:string|null;teacherName:string;lessonContent:string;homeworkContent:string;examContent:string;attendance:AttendanceInfo;homeworkResult:HomeworkResult;exams:Exam[]};
type ReadReceipt={lessonId:string;viewedAt:string};
type ReportComment={id:string;parentId:string|null;body:string;authorName:string;authorRole:string;createdAt:string;canDelete:boolean;isDeleted:boolean};

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};
const homeworkLabel:Record<string,string>={complete:"완료",partial:"일부 완료",missing:"미제출",excused:"확인 제외"};

export function FamilyLearningReportFeed({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
  const [items,setItems]=useState<Report[]>([]);
  const [reads,setReads]=useState<Record<string,string>>({});
  const [subject,setSubject]=useState("전체");
  const [loading,setLoading]=useState(true);
  const [unavailable,setUnavailable]=useState(false);
  const [readTracking,setReadTracking]=useState(false);
  const [confirming,setConfirming]=useState<string|null>(null);
  const [selected,setSelected]=useState<Report|null>(null);
  const [canComment,setCanComment]=useState(false);

  useEffect(()=>{
    let active=true;
    void Promise.resolve().then(async()=>{
      if(!active)return;
      setLoading(true);setUnavailable(false);setReadTracking(false);setReads({});setSelected(null);
      const reportResult=await supabase.rpc("family_completed_learning_reports",{p_student_id:studentId,p_limit:20});
      if(!active)return;
      if(reportResult.error){setUnavailable(true);setItems([]);setLoading(false);return;}
      setItems((reportResult.data??[]) as Report[]);
      const readResult=await supabase.rpc("family_learning_report_reads",{p_student_id:studentId});
      if(!active)return;
      if(!readResult.error){
        const next:Record<string,string>={};
        for(const receipt of (readResult.data??[]) as ReadReceipt[])next[receipt.lessonId]=receipt.viewedAt;
        setReads(next);setReadTracking(true);
      }
      setLoading(false);
    });
    return()=>{active=false};
  },[studentId,supabase]);
  useEffect(()=>{void supabase.rpc("family_can_report_comment").then(({data,error})=>setCanComment(!error&&data===true))},[supabase]);
  useEffect(()=>{if(loading)return;try{const detail=JSON.parse(sessionStorage.getItem("hansalmae:family-report-target")??"null") as {lessonId?:string;studentId?:string}|null;if(!detail?.lessonId||(detail.studentId&&detail.studentId!==studentId))return;const target=items.find(item=>item.lessonId===detail.lessonId);if(target){setSelected(target);sessionStorage.removeItem("hansalmae:family-report-target")}}catch{sessionStorage.removeItem("hansalmae:family-report-target")}},[items,loading,studentId]);
  useEffect(()=>{const openReport=(event:Event)=>{const detail=(event as CustomEvent<{lessonId?:string;studentId?:string}>).detail;if(!detail?.lessonId||(detail.studentId&&detail.studentId!==studentId))return;const target=items.find(item=>item.lessonId===detail.lessonId);if(target){setSelected(target);sessionStorage.removeItem("hansalmae:family-report-target")}};window.addEventListener("hansalmae:open-family-report",openReport);return()=>window.removeEventListener("hansalmae:open-family-report",openReport)},[items,studentId]);

  useEffect(()=>{
    if(!selected)return;
    const close=(event:KeyboardEvent)=>{if(event.key==="Escape")setSelected(null)};
    document.addEventListener("keydown",close);
    return()=>document.removeEventListener("keydown",close);
  },[selected]);

  const subjects=useMemo(()=>Array.from(new Set(items.map(item=>item.subject).filter(Boolean))),[items]);
  const selectedSubject=subject==="전체"||subjects.includes(subject)?subject:"전체";
  const visibleItems=useMemo(()=>selectedSubject==="전체"?items:items.filter(item=>item.subject===selectedSubject),[items,selectedSubject]);
  const groups=useMemo(()=>{
    const grouped=new Map<string,Report[]>();
    for(const item of visibleItems){const current=grouped.get(item.lessonDate)??[];current.push(item);grouped.set(item.lessonDate,current);}
    return Array.from(grouped.entries());
  },[visibleItems]);
  const unreadCount=readTracking?items.filter(item=>!reads[item.lessonId]).length:0;

  async function confirmRead(lessonId:string){
    if(!readTracking||reads[lessonId]||confirming)return;
    setConfirming(lessonId);
    const {data,error}=await supabase.rpc("mark_family_learning_report_read",{p_student_id:studentId,p_lesson_id:lessonId});
    if(!error)setReads(current=>({...current,[lessonId]:String(data??new Date().toISOString())}));
    setConfirming(null);
  }

  if(unavailable)return null;
  return <section className="family-report-feed" aria-label="수업 학습 리포트">
    <header className="family-report-feed-title">
      <div><p className="eyebrow">하루하루 쌓이는 기록</p><h2>학습 피드</h2><span>오늘 무엇을 배우고 어떻게 해냈는지 확인하세요.</span></div>
      {readTracking&&unreadCount>0&&<strong className="family-report-unread-count">새 기록 {unreadCount}</strong>}
    </header>
    {subjects.length>1&&<nav className="family-report-subject-filter" aria-label="과목 필터"><button type="button" className={selectedSubject==="전체"?"active":""} onClick={()=>setSubject("전체")}>전체</button>{subjects.map(name=><button type="button" key={name} className={selectedSubject===name?"active":""} onClick={()=>setSubject(name)}>{name}</button>)}</nav>}
    {loading?<p className="family-report-empty">학습 기록을 불러오는 중이에요…</p>:!items.length?<p className="family-report-empty">아직 도착한 학습 기록이 없습니다.</p>:<div className="family-report-date-list">{groups.map(([date,reports])=><section className="family-report-date-group" key={date}><header><div><time>{formatDateTitle(date)}</time><span>{formatDateWeekday(date)}</span></div><small>{reports.length}개 수업</small></header><div className="family-report-list">{reports.map(item=><ReportCard key={item.lessonId} item={item} readAt={reads[item.lessonId]??null} readTracking={readTracking} onOpen={()=>setSelected(item)}/>)}</div></section>)}</div>}
    {selected&&<ReportDetail supabase={supabase} studentId={studentId} item={selected} canComment={canComment} readAt={reads[selected.lessonId]??null} readTracking={readTracking} confirming={confirming===selected.lessonId} onClose={()=>setSelected(null)} onConfirm={()=>void confirmRead(selected.lessonId)}/>}
  </section>;
}

function ReportCard({item,readAt,readTracking,onOpen}:{item:Report;readAt:string|null;readTracking:boolean;onOpen:()=>void}){
  const attendance=item.attendance;
  const firstExam=item.exams[0]??null;
  const preview=item.lessonContent||item.examContent||item.homeworkContent||firstExam?.evaluation||"수업 기록이 도착했어요.";
  return <article className={`family-report-card ${readTracking&&!readAt?"unread":""}`}>
    <button type="button" className="family-report-card-main" onClick={onOpen} aria-label={`${item.className} 리포트 자세히 보기`}>
      <span className="family-report-subject-mark" aria-hidden="true">{item.subject?.slice(0,1)||"수"}</span>
      <span className="family-report-subject">
        <span className="family-report-card-labels"><span>{item.subject}</span>{readTracking&&!readAt&&<em>NEW</em>}</span>
        <strong>{item.className}</strong>
        <small>{formatTime(item.startsAt)} · {item.teacherName}{item.room?` · ${item.room}`:""}</small>
        <p>{preview}</p>
        <span className="family-report-card-meta">{firstExam&&<em>{firstExam.score===null?(firstExam.examTitle||"시험 평가"):`${firstExam.examTitle||"시험"} ${formatScore(firstExam.score)}/${formatScore(firstExam.maxScore)}`}</em>}{item.homeworkResult&&<em>숙제 {homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}</em>}</span>
      </span>
      {attendance&&<strong className={`family-attendance-badge ${attendance.status}`}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}
      <span className="family-report-open">자세히 보기 <b>›</b></span>
    </button>
  </article>;
}

function ReportDetail({supabase,studentId,item,canComment,readAt,readTracking,confirming,onClose,onConfirm}:{supabase:SupabaseClient;studentId:string;item:Report;canComment:boolean;readAt:string|null;readTracking:boolean;confirming:boolean;onClose:()=>void;onConfirm:()=>void}){
  const attendance=item.attendance;
  const attendanceMemo=[attendance?.absenceReason,attendance?.note].filter(Boolean).join(" · ");
  const teacherFeedbacks=item.exams.filter(exam=>exam.feedback.trim()).map(exam=>({label:exam.examTitle||exam.examType||"시험",text:exam.feedback.trim()}));
  return <div className="family-report-detail-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}>
    <section className="family-report-detail" role="dialog" aria-modal="true" aria-labelledby="family-report-detail-title">
      <header className="family-report-detail-head"><button type="button" onClick={onClose} aria-label="상세 리포트 닫기">‹</button><div><small>{formatFullDate(item.lessonDate)}</small><h2 id="family-report-detail-title">수업 상세 리포트</h2></div><span/></header>
      <div className="family-report-detail-scroll">
        <section className="family-report-detail-hero"><div className="family-report-card-labels"><span>{item.subject}</span></div><div><h3>{item.className}</h3>{attendance&&<strong className={`family-attendance-badge ${attendance.status}`}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}</div><p>{formatTime(item.startsAt)} · {item.teacherName}{item.room?` · ${item.room}`:""}</p></section>
        <div className="family-report-detail-sections">
          {item.lessonContent&&<ReportSection icon="book" title="오늘 수업" text={item.lessonContent}/>}
          {item.examContent&&<ReportSection icon="chart" title="오늘 시험·평가" text={item.examContent}/>}
          {item.exams.length>0&&<section className="family-report-section family-report-exam-section"><i><HansalmaeIcon name="chart" size={18}/></i><div><b>개인별 시험 결과</b><div className="family-report-exams">{item.exams.map(exam=>{const convertedScore=getConvertedScore(exam);return <div key={exam.id}><span><strong>{exam.examTitle||exam.examType||"시험"}</strong>{exam.evaluation&&<small>{exam.evaluation}</small>}</span><em>{exam.score===null?"평가":<><strong>{formatScore(exam.score)} / {formatScore(exam.maxScore)}</strong>{convertedScore!==null&&<small>100점 환산 {formatScore(convertedScore)}점</small>}</>}</em></div>})}</div></div></section>}
          {item.homeworkResult&&<section className="family-report-section"><i><HansalmaeIcon name="check" size={18}/></i><div><b>지난 숙제 검사</b><p><strong className={`homework-result ${item.homeworkResult.status}`}>{homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}</strong>{item.homeworkResult.note&&<span> · {item.homeworkResult.note}</span>}</p></div></section>}
          {item.homeworkContent&&<ReportSection icon="edit" title="과제 및 복습" text={item.homeworkContent}/>}
          {attendanceMemo&&<ReportSection icon="notice" title="출결 메모" text={attendanceMemo}/>}
        </div>
        {teacherFeedbacks.length>0&&<section className="family-teacher-feedback"><span className="family-teacher-feedback-icon"><HansalmaeIcon name="chat" size={19}/></span><div><b>{item.teacherName} 선생님 한마디</b>{teacherFeedbacks.map((feedback,index)=><p key={`${feedback.label}-${index}`}><strong>{feedback.label}</strong><span>{feedback.text}</span></p>)}</div></section>}
        {canComment&&<FamilyReportComments supabase={supabase} studentId={studentId} lessonId={item.lessonId} teacherName={item.teacherName}/>}
      </div>
      {readTracking&&<footer className="family-report-confirm"><span>{readAt?`확인 완료 · ${formatReadTime(readAt)}`:"내용을 확인했다면 표시를 남겨주세요."}</span>{!readAt&&<button type="button" disabled={confirming} onClick={onConfirm}><HansalmaeIcon name="check" size={16}/>{confirming?"처리 중…":"확인했어요"}</button>}</footer>}
    </section>
  </div>;
}

function FamilyReportComments({supabase,studentId,lessonId,teacherName}:{supabase:SupabaseClient;studentId:string;lessonId:string;teacherName:string}){
  const[items,setItems]=useState<ReportComment[]>([]);const[body,setBody]=useState("");const[loading,setLoading]=useState(true);const[saving,setSaving]=useState(false);const[deleting,setDeleting]=useState<string|null>(null);const[error,setError]=useState("");
  const load=useCallback(async()=>{setLoading(true);const{data,error:nextError}=await supabase.rpc("family_report_comments",{p_student_id:studentId,p_lesson_id:lessonId});setItems(nextError?[]:((data??[]) as ReportComment[]));setError(nextError?"댓글을 불러오지 못했습니다.":"");setLoading(false)},[lessonId,studentId,supabase]);
  useEffect(()=>{void Promise.resolve().then(load)},[load]);
  async function submit(){const next=body.trim();if(!next||saving)return;setSaving(true);setError("");const{error:nextError}=await supabase.rpc("family_add_report_comment",{p_student_id:studentId,p_lesson_id:lessonId,p_body:next});if(nextError)setError("댓글을 등록하지 못했습니다.");else{setBody("");await load()}setSaving(false)}
  async function remove(item:ReportComment){if(deleting||!item.canDelete||!await appConfirm({eyebrow:"댓글 삭제",title:"작성한 댓글을 삭제할까요?",notice:"선생님이 남긴 답변은 그대로 유지됩니다.",confirmLabel:"댓글 삭제",tone:"danger"}))return;setDeleting(item.id);setError("");const{error:nextError}=await supabase.rpc("delete_report_comment",{p_comment_id:item.id});if(nextError)setError("댓글을 삭제하지 못했습니다.");else await load();setDeleting(null)}
  const roots=items.filter(item=>!item.parentId);
  return (
    <section className="family-report-comments">
      <header>
        <div className="family-comment-heading-icon"><HansalmaeIcon name="chat" size={18}/></div>
        <span><b>선생님과 댓글</b><small>{teacherName} 선생님과 수업에 대해 이야기해 보세요.</small></span>
        <em>{items.length ? `${items.length}개` : "새 대화"}</em>
      </header>
      {loading ? <p className="family-comment-empty">댓글을 불러오는 중이에요…</p> : roots.length ? (
        <div className="family-comment-list">
          {roots.map(root => <article key={root.id}>
            <div className="family-comment-author">
              <i>{root.authorName.slice(0,1)}</i>
              <span><strong>{root.authorName} 학부모님</strong><time>{formatCommentTime(root.createdAt)}</time></span>
              {root.canDelete&&<button type="button" className="report-comment-delete" disabled={deleting===root.id} onClick={()=>void remove(root)}>{deleting===root.id?"삭제 중…":"삭제"}</button>}
            </div>
            <p className={`family-comment-bubble ${root.isDeleted?"deleted":""}`}>{root.body}</p>
            {items.filter(reply => reply.parentId === root.id).map(reply => <section key={reply.id}>
              <div><i>{reply.authorName.slice(0,1)}</i><b>{reply.authorName} 선생님</b></div>
              <p>{reply.body}</p>
              <time>{formatCommentTime(reply.createdAt)}</time>
            </section>)}
          </article>)}
        </div>
      ) : <p className="family-comment-empty">아직 댓글이 없어요.<small>수업에 관해 궁금한 점을 편하게 남겨주세요.</small></p>}
      <div className="family-comment-compose">
        <textarea maxLength={500} rows={2} value={body} onChange={event=>setBody(event.target.value)} placeholder="선생님께 전할 댓글을 입력하세요"/>
        <footer><span>{body.length}/500</span><button type="button" disabled={!body.trim()||saving} onClick={()=>void submit()}>{saving?"등록 중…":"댓글 등록"}</button></footer>
      </div>
      {error&&<p className="family-comment-error">{error}</p>}
    </section>
  )
}

function ReportSection({icon,title,text}:{icon:"book"|"edit"|"notice"|"chart";title:string;text:string}){return <section className="family-report-section"><i><HansalmaeIcon name={icon} size={18}/></i><div><b>{title}</b><p>{text}</p></div></section>}
function dateValue(value:string){return new Date(`${value}T12:00:00+09:00`)}
function formatDateTitle(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric"}).format(dateValue(value))}
function formatDateWeekday(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",weekday:"long"}).format(dateValue(value))}
function formatFullDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric",weekday:"long"}).format(dateValue(value))}
function formatTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
function getConvertedScore(exam:Exam){if(exam.score===null)return null;if(exam.percent!==null&&Number.isFinite(Number(exam.percent)))return Math.round(Number(exam.percent)*10)/10;if(!Number.isFinite(Number(exam.maxScore))||Number(exam.maxScore)<=0)return null;return Math.round(Number(exam.score)/Number(exam.maxScore)*1000)/10}
function formatCommentTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
