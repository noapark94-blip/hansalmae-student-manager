"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile, StudentRow } from "./supabase";
import { HansalmaeIcon } from "./hansalmae-icons";
import styles from "./report-center.module.css";

type ReportType = "daily" | "weekly";
type Lesson = { lessonId:string;lessonDate:string;startsAt:string;className:string;subject:string;source:"regular"|"makeup"|"extra"|"correction";teacherName:string;room:string|null;lessonContent:string;homeworkContent:string;examContent:string;attendance:{status:string;lateMinutes:number|null;note:string}|null;homeworkResult:{status:string;note:string}|null;exams:{id:string;examTitle:string;examType:string;score:number|null;maxScore:number;evaluation:string;feedback:string}[] };
type ListItem={id:string;studentId:string;studentName:string;reportType:ReportType;periodStart:string;periodEnd:string;status:"draft"|"published";publishedAt:string|null;viewedAt:string|null};
type Detail={id:string;studentId:string;studentName:string;school:string;grade:string;reportType:ReportType;periodStart:string;periodEnd:string;teacherComment:string;snapshot:Lesson[];status:"draft"|"published";publishedAt:string|null;viewedAt:string|null};

const kindLabel={regular:"정규수업",makeup:"보강",extra:"추가수업",correction:"첨삭"};
const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"인정결석",scheduled:"예정"};
const homeworkLabel:Record<string,string>={complete:"완료",partial:"일부 완료",missing:"미제출",not_checked:"미확인",excused:"확인 제외"};

export function ReportCenter({supabase,profile,students,initialReportId}:{supabase:SupabaseClient;profile:Profile;students:StudentRow[];initialReportId?:string|null}){
  const staff=profile.role==="admin"||profile.role==="teacher";
  const [type,setType]=useState<ReportType>("daily");
  const [anchor,setAnchor]=useState(today());
  const [studentId,setStudentId]=useState("");
  const [studentQuery,setStudentQuery]=useState("");
  const [subjectFilter,setSubjectFilter]=useState("all");
  const [classFilter,setClassFilter]=useState("all");
  const [gradeFilter,setGradeFilter]=useState("all");
  const [schoolFilter,setSchoolFilter]=useState("all");
  const [studentSort,setStudentSort]=useState<"name"|"school"|"grade">("name");
  const [items,setItems]=useState<ListItem[]>([]);
  const [detail,setDetail]=useState<Detail|null>(null);
  const [snapshot,setSnapshot]=useState<Lesson[]>([]);
  const [comment,setComment]=useState("");
  const [loading,setLoading]=useState(true);
  const [saving,setSaving]=useState(false);
  const [message,setMessage]=useState("");
  const period=useMemo(()=>periodFor(type,anchor),[type,anchor]);

  const loadList=useCallback(async()=>{
    const {data,error}=await supabase.rpc("learning_report_list");
    if(error){setMessage(error.message);return [] as ListItem[]}
    const rows=(data??[]) as ListItem[];setItems(rows);return rows;
  },[supabase]);

  const openReport=useCallback(async(id:string)=>{
    setLoading(true);setMessage("");
    const {data,error}=await supabase.rpc("learning_report_detail",{p_publication_id:id});
    if(error){setMessage(error.message);setLoading(false);return}
    const next=data as Detail;setDetail(next);setType(next.reportType);setAnchor(next.periodStart);setStudentId(next.studentId);setSnapshot(next.snapshot??[]);setComment(next.teacherComment??"");
    if(!staff&&!next.viewedAt) await supabase.rpc("mark_learning_report_read",{p_publication_id:id});
    setLoading(false);
  },[staff,supabase]);

  useEffect(()=>{void (async()=>{const rows=await loadList();if(initialReportId)await openReport(initialReportId);else if(!staff&&rows[0])await openReport(rows[0].id);else setLoading(false)})()},[initialReportId,loadList,openReport,staff]);
  const studentFilterOptions=useMemo(()=>{
    const enrollments=students.flatMap(student=>student.enrollments.filter(item=>item.status==="active"&&item.classes));
    const subjects=Array.from(new Set(enrollments.map(item=>item.classes?.subject).filter((value):value is string=>Boolean(value)))).sort((a,b)=>a.localeCompare(b,"ko"));
    const classes=Array.from(new Map(enrollments.filter(item=>subjectFilter==="all"||item.classes?.subject===subjectFilter).map(item=>[item.class_id,{id:item.class_id,name:item.classes?.name??"클래스"}])).values()).sort((a,b)=>a.name.localeCompare(b.name,"ko"));
    const grades=Array.from(new Set(students.map(student=>student.grade).filter((value):value is string=>Boolean(value)))).sort((a,b)=>a.localeCompare(b,"ko"));
    const schools=Array.from(new Set(students.map(student=>student.school).filter((value):value is string=>Boolean(value)))).sort((a,b)=>a.localeCompare(b,"ko"));
    return{subjects,classes,grades,schools};
  },[students,subjectFilter]);
  const visibleStudents=useMemo(()=>{
    const query=studentQuery.trim().toLowerCase();
    return students.filter(student=>{
      const active=student.enrollments.filter(item=>item.status==="active");
      return (!query||[student.name,student.school??"",student.grade??"",...active.flatMap(item=>[item.classes?.subject??"",item.classes?.name??""])].some(value=>value.toLowerCase().includes(query)))
        &&(subjectFilter==="all"||active.some(item=>item.classes?.subject===subjectFilter))
        &&(classFilter==="all"||active.some(item=>item.class_id===classFilter))
        &&(gradeFilter==="all"||student.grade===gradeFilter)
        &&(schoolFilter==="all"||student.school===schoolFilter);
    }).sort((a,b)=>studentSort==="school"?(a.school??"").localeCompare(b.school??"","ko")||a.name.localeCompare(b.name,"ko"):studentSort==="grade"?(a.grade??"").localeCompare(b.grade??"","ko")||a.name.localeCompare(b.name,"ko"):a.name.localeCompare(b.name,"ko"));
  },[classFilter,gradeFilter,schoolFilter,studentQuery,studentSort,students,subjectFilter]);
  const selectedStudentId=visibleStudents.some(student=>student.id===studentId)?studentId:visibleStudents[0]?.id??"";
  const resetStudentSelection=()=>{setStudentId("");setDetail(null)};

  async function preview(){
    if(!selectedStudentId)return;setLoading(true);setMessage("");setDetail(null);
    const existing=items.find(item=>item.studentId===selectedStudentId&&item.reportType===type&&item.periodStart===period.start);
    const {data,error}=await supabase.rpc("staff_learning_report_source",{p_student_id:selectedStudentId,p_from:period.start,p_to:period.end});
    if(error){setMessage(error.message);setLoading(false);return}
    setSnapshot((data??[]) as Lesson[]);
    if(existing){const result=await supabase.rpc("learning_report_detail",{p_publication_id:existing.id});if(!result.error){setDetail(result.data as Detail);setComment((result.data as Detail).teacherComment??"")}}
    else setComment("");
    setLoading(false);
  }

  async function save(publish:boolean){
    if(!selectedStudentId)return;setSaving(true);setMessage("");
    const {data,error}=await supabase.rpc("staff_save_learning_report",{p_student_id:selectedStudentId,p_report_type:type,p_period_start:period.start,p_period_end:period.end,p_teacher_comment:comment,p_snapshot:snapshot,p_publish:publish});
    if(error)setMessage(error.message);else{setMessage(publish?"리포트를 발행했습니다.":"임시 저장했습니다.");await loadList();await openReport(String(data))}
    setSaving(false);
  }

  async function copyLink(){
    if(!detail||detail.status!=="published")return;
    const url=`${window.location.origin}/?report=${detail.id}`;
    const label=detail.reportType==="daily"?"데일리":"위클리";
    await navigator.clipboard.writeText(`[한살매 수업노트] ${detail.studentName} 학생 ${label} 리포트가 도착했습니다.\n로그인 후 확인해 주세요.\n${url}`);
    setMessage("카카오톡에 붙여넣을 안내문과 링크를 복사했습니다.");
  }

  const counts=useMemo(()=>snapshot.reduce((acc,row)=>{acc[row.source]=(acc[row.source]??0)+1;return acc},{regular:0,makeup:0,extra:0,correction:0} as Record<string,number>),[snapshot]);
  const selectedName=students.find(s=>s.id===selectedStudentId)?.name??detail?.studentName??"학생";
  return <section className={styles.center}>
    <header className={styles.hero}><div><p>한살매 수업노트</p><h1>데일리 · 위클리 리포트</h1><span>{staff?"수업과 첨삭 기록을 한 장으로 정리해 공유하세요.":"선생님이 정리한 학습 흐름을 한눈에 확인하세요."}</span></div><HansalmaeIcon name="book" size={30}/></header>
    <nav className={styles.tabs}><button className={type==="daily"?styles.active:""} onClick={()=>{setType("daily");setDetail(null)}}>데일리</button><button className={type==="weekly"?styles.active:""} onClick={()=>{setType("weekly");setDetail(null)}}>위클리</button></nav>
    {staff?<div className={styles.workspace}>
      <aside className={styles.controls}>
        <div className={styles.studentFilters}>
          <label className={styles.studentSearch}><i><HansalmaeIcon name="students" size={16}/><input value={studentQuery} onChange={e=>{setStudentQuery(e.target.value);resetStudentSelection()}} placeholder="이름, 학교, 과목 검색" aria-label="리포트 학생 검색"/>{studentQuery&&<button type="button" onClick={()=>{setStudentQuery("");resetStudentSelection()}} aria-label="학생 검색어 지우기">×</button>}</i></label>
          <FilterSelect label="과목" value={subjectFilter} onChange={value=>{setSubjectFilter(value);setClassFilter("all");resetStudentSelection()}} allLabel="전체 과목" options={studentFilterOptions.subjects.map(value=>({value,label:value}))}/>
          <FilterSelect label="클래스" value={classFilter} onChange={value=>{setClassFilter(value);resetStudentSelection()}} allLabel="전체 클래스" options={studentFilterOptions.classes.map(item=>({value:item.id,label:item.name}))}/>
          <FilterSelect label="학년" value={gradeFilter} onChange={value=>{setGradeFilter(value);resetStudentSelection()}} allLabel="전체 학년" options={studentFilterOptions.grades.map(value=>({value,label:value}))}/>
          <FilterSelect label="학교" value={schoolFilter} onChange={value=>{setSchoolFilter(value);resetStudentSelection()}} allLabel="전체 학교" options={studentFilterOptions.schools.map(value=>({value,label:value}))}/>
          <FilterSelect label="정렬" value={studentSort} onChange={value=>{setStudentSort(value as "name"|"school"|"grade");resetStudentSelection()}} options={[{value:"name",label:"이름순"},{value:"school",label:"학교순"},{value:"grade",label:"학년순"}]}/>
        </div>
        <div className={styles.reportSelection}>
          <label>학생<select value={selectedStudentId} onChange={e=>{setStudentId(e.target.value);setDetail(null)}} disabled={!visibleStudents.length}><option value="">{visibleStudents.length?"학생 선택":"검색 결과 없음"}</option>{visibleStudents.map(s=><option key={s.id} value={s.id}>{s.name} · {s.school??"학교 미입력"} {s.grade??""}</option>)}</select></label>
          <label>{type==="daily"?"날짜":"주간 기준일"}<input type="date" value={anchor} onChange={e=>{setAnchor(e.target.value);setDetail(null)}}/></label>
          <span className={styles.periodText}>{formatPeriod(period.start,period.end)}</span>
          <span className={styles.resultCount}>검색 결과 <b>{visibleStudents.length}</b>명</span>
          <button className={styles.primary} onClick={()=>void preview()} disabled={!selectedStudentId||loading}>{loading?"불러오는 중…":"리포트 미리보기"}</button>
        </div>
        <section className={styles.recent}><b>최근 리포트</b><div className={styles.history}>{items.filter(i=>i.reportType===type).slice(0,12).map(item=><button key={item.id} onClick={()=>void openReport(item.id)}><span>{item.studentName}<small>{formatPeriod(item.periodStart,item.periodEnd)}</small></span><em className={item.status===dayStatus("published")?styles.published:styles.draft}>{item.status==="published"?(item.viewedAt?"열람":"발행"):"임시"}</em></button>)}</div>{!items.some(item=>item.reportType===type)&&<p>아직 저장하거나 발행한 {type==="daily"?"데일리":"위클리"} 리포트가 없습니다.</p>}</section>
      </aside>
      <main className={styles.preview}>{snapshot.length||detail?<><ReportPaper detail={detail} name={selectedName} type={type} period={period} lessons={snapshot} comment={comment} counts={counts}/><label className={styles.comment}>선생님 한마디<textarea value={comment} onChange={e=>setComment(e.target.value)} placeholder="오늘의 성취, 다음 주 목표, 가정에서 확인할 내용을 적어주세요." rows={4}/></label><div className={styles.actions}><button onClick={()=>void save(false)} disabled={saving}>임시 저장</button><button className={styles.primary} onClick={()=>void save(true)} disabled={saving}>{saving?"저장 중…":"발행하기"}</button>{detail?.status==="published"&&<button onClick={()=>void copyLink()}><HansalmaeIcon name="chat" size={16}/> 카카오톡 링크 복사</button>}</div></>:<Empty text="학생과 기간을 선택해 미리보기를 눌러주세요."/>}</main>
    </div>:<div className={styles.familyLayout}><aside className={styles.familyList}>{items.filter(i=>i.reportType===type).map(item=><button className={detail?.id===item.id?styles.selected:""} key={item.id} onClick={()=>void openReport(item.id)}><b>{item.studentName}</b><span>{formatPeriod(item.periodStart,item.periodEnd)}</span>{!item.viewedAt&&<em>NEW</em>}</button>)}</aside><main className={styles.preview}>{loading?<Empty text="리포트를 불러오는 중이에요…"/>:detail?<ReportPaper detail={detail} name={detail.studentName} type={detail.reportType} period={{start:detail.periodStart,end:detail.periodEnd}} lessons={detail.snapshot} comment={detail.teacherComment} counts={detail.snapshot.reduce((a,r)=>{a[r.source]=(a[r.source]??0)+1;return a},{regular:0,makeup:0,extra:0,correction:0} as Record<string,number>)}/>:<Empty text="아직 발행된 리포트가 없습니다."/>}</main></div>}
    {message&&<p className={styles.message} role="status">{message}</p>}
  </section>
}

function ReportPaper({detail,name,type,period,lessons,comment,counts}:{detail:Detail|null;name:string;type:ReportType;period:{start:string;end:string};lessons:Lesson[];comment:string;counts:Record<string,number>}){
  const groups=lessons.reduce((map,item)=>{const list=map.get(item.lessonDate)??[];list.push(item);map.set(item.lessonDate,list);return map},new Map<string,Lesson[]>());
  return <article className={styles.paper}><header><div><small>{type==="daily"?"DAILY REPORT":"WEEKLY REPORT"}</small><h2>{name} 학생 학습 리포트</h2><p>{formatPeriod(period.start,period.end)}</p></div>{detail?.status==="published"&&<span className={styles.seal}>발행 완료</span>}</header><div className={styles.summary}>{(["regular","makeup","extra","correction"] as const).map(kind=><div key={kind}><b>{counts[kind]??0}</b><span>{kindLabel[kind]}</span></div>)}</div>{!lessons.length?<Empty text="이 기간에 완료된 수업·첨삭 기록이 없습니다."/>:Array.from(groups).map(([date,rows])=><section className={styles.day} key={date}><h3>{formatDay(date)}</h3>{rows.map(row=><article className={styles.lesson} key={`${row.source}-${row.lessonId}`}><header><span className={`${styles.kind} ${styles[row.source]}`}>{kindLabel[row.source]}</span><div><b>{row.subject} · {row.className}</b><small>{formatTime(row.startsAt)} · {row.teacherName}{row.room?` · ${row.room}`:""}</small></div>{row.attendance&&<em>{attendanceLabel[row.attendance.status]??row.attendance.status}{row.attendance.status==="late"&&row.attendance.lateMinutes?` ${row.attendance.lateMinutes}분`:""}</em>}</header><div className={styles.lessonBody}>{row.lessonContent&&<Info title={row.source==="correction"?"첨삭 내용":"수업 내용"} text={row.lessonContent}/>} {row.examContent&&<Info title="시험·평가" text={row.examContent}/>} {row.exams?.map(exam=><Info key={exam.id} title={exam.examTitle||exam.examType||"평가"} text={`${exam.score===null?"평가":`${exam.score} / ${exam.maxScore}`} ${exam.evaluation||exam.feedback}`.trim()}/>)} {row.homeworkResult&&<Info title="지난 숙제" text={`${homeworkLabel[row.homeworkResult.status]??row.homeworkResult.status}${row.homeworkResult.note?` · ${row.homeworkResult.note}`:""}`}/>} {row.homeworkContent&&<Info title="다음 학습" text={row.homeworkContent}/>}</div></article>)}</section>)}{comment&&<footer><HansalmaeIcon name="chat" size={20}/><div><b>선생님 한마디</b><p>{comment}</p></div></footer>}</article>
}
function FilterSelect({label,value,onChange,allLabel,options}:{label:string;value:string;onChange:(value:string)=>void;allLabel?:string;options:{value:string;label:string}[]}){return <label><select aria-label={label} value={value} onChange={event=>onChange(event.target.value)}>{allLabel&&<option value="all">{allLabel}</option>}{options.map(option=><option key={option.value} value={option.value}>{option.label}</option>)}</select></label>}
function Info({title,text}:{title:string;text:string}){return <div className={styles.info}><b>{title}</b><p>{text}</p></div>}
function Empty({text}:{text:string}){return <div className={styles.empty}><HansalmaeIcon name="book" size={28}/><p>{text}</p></div>}
function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul"}).format(new Date())}
function periodFor(type:ReportType,anchor:string){if(type==="daily")return{start:anchor,end:anchor};const date=new Date(`${anchor}T12:00:00+09:00`);const day=(date.getDay()+6)%7;date.setDate(date.getDate()-day);const start=todayFrom(date);date.setDate(date.getDate()+6);return{start,end:todayFrom(date)}}
function todayFrom(date:Date){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul"}).format(date)}
function formatPeriod(start:string,end:string){const f=(v:string)=>new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"short",day:"numeric"}).format(new Date(`${v}T12:00:00+09:00`));return start===end?f(start):`${f(start)} – ${f(end)}`}
function formatDay(v:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric",weekday:"long"}).format(new Date(`${v}T12:00:00+09:00`))}
function formatTime(v:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(v))}
function dayStatus<T extends "published">(value:T){return value}
