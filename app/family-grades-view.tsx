"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { ExamTrendModal } from "./family-learning-report-feed";

type Child={id:string;name:string;school:string|null;grade:string|null};
type Dashboard={children:Child[];selectedStudent:Child|null};
type RecordType="school"|"mock";
type AcademicRecord={id:string;recordType:RecordType;academicYear:number;semester:number|null;examDate:string;examName:string;subject:string;score:number|null;grade:number|null;achievementLevel:string|null;rank:number|null;cohortSize:number|null;schoolAverage:number|null;standardScore:number|null;percentile:number|null;note:string|null};
type AcademicData={student:Child|null;records:AcademicRecord[]};
type GradeTab="academy"|RecordType;

export function FamilyGradesView({supabase,profile}:{supabase:SupabaseClient;profile:Profile}){
  const[data,setData]=useState<Dashboard|null>(null);const[academic,setAcademic]=useState<AcademicData|null>(null);
  const[selectedId,setSelectedId]=useState<string|null>(null);const[tab,setTab]=useState<GradeTab>("academy");
  const[loading,setLoading]=useState(true);const[error,setError]=useState("");
  const load=useCallback(async(id:string|null)=>{setLoading(true);setError("");const[dashboardResult,academicResult]=await Promise.all([
    supabase.rpc("family_live_dashboard",{p_student_id:id}),supabase.rpc("family_academic_records",{p_student_id:id})
  ]);if(dashboardResult.error||academicResult.error){setError("성적 정보를 불러오지 못했습니다.");setLoading(false);return}
    const next=dashboardResult.data as Dashboard;setData(next);setAcademic(academicResult.data as AcademicData);setSelectedId(next.selectedStudent?.id??null);setLoading(false);
  },[supabase]);
  useEffect(()=>{void load(null)},[load]);
  const student=data?.selectedStudent;const isMiddle=/^중\s*[1-3]/.test(student?.grade?.trim()??"");
  useEffect(()=>{if(isMiddle&&tab==="mock")setTab("school")},[isMiddle,tab]);
  if(loading&&!data)return <section className="panel hub-message">성적 정보를 불러오는 중이에요…</section>;
  if(error&&!data)return <section className="panel hub-message error">{error}</section>;
  return <div className="family-grades-page">
    <header className="family-grades-heading"><p>{profile.role==="guardian"?"자녀 성장 기록":"나의 성장 기록"}</p><h1>성적확인</h1><span>학원 시험과 학교 성적의 흐름을 필요한 정보만 모아 확인하세요.</span></header>
    {error&&<p className="attendance-error">{error}</p>}
    {student?<>
      {profile.role==="guardian"&&(data?.children.length??0)>1&&<div className="family-grades-child-select"><label htmlFor="family-grades-child">자녀 선택</label><select id="family-grades-child" value={selectedId??""} onChange={event=>void load(event.target.value)}>{data?.children.map(child=><option key={child.id} value={child.id}>{child.name} · {[child.school,child.grade].filter(Boolean).join(" ")}</option>)}</select></div>}
      <nav className={`family-grade-tabs${isMiddle?" middle":""}`} aria-label="성적 종류"><button className={tab==="academy"?"active":""} onClick={()=>setTab("academy")}>학원 시험</button><button className={tab==="school"?"active":""} onClick={()=>setTab("school")}>학교 내신</button>{!isMiddle&&<button className={tab==="mock"?"active":""} onClick={()=>setTab("mock")}>모의고사</button>}</nav>
      {tab==="academy"?<ExamTrendModal supabase={supabase} studentId={student.id} initialSubject="영어" embedded onClose={()=>setTab("school")}/>:<AcademicRecords records={academic?.records??[]} type={tab} isMiddle={isMiddle}/>} 
    </>:<section className="panel family-empty"><b>연결된 학생 정보가 없습니다.</b></section>}
  </div>;
}

function AcademicRecords({records,type,isMiddle}:{records:AcademicRecord[];type:RecordType;isMiddle:boolean}){
  const typed=useMemo(()=>records.filter(item=>item.recordType===type),[records,type]);const subjects=useMemo(()=>Array.from(new Set(typed.map(item=>item.subject))),[typed]);const[subject,setSubject]=useState("");const[historyOpen,setHistoryOpen]=useState(false);
  useEffect(()=>{setSubject(subjects[0]??"");setHistoryOpen(false)},[subjects,type]);const visible=subject?typed.filter(item=>item.subject===subject):typed;const latest=visible[0];
  const scores=visible.map(item=>type==="mock"?(item.percentile??item.score):item.score).filter((value):value is number=>value!==null);const average=scores.length?Math.round(scores.reduce((sum,value)=>sum+value,0)/scores.length):null;
  return <section className="family-grade-section">
    {subjects.length>0&&<div className="family-grade-subject-panel"><div className="family-grade-subjects" aria-label={`${type==="school"?"학교 내신":"모의고사"} 과목 선택`}>{subjects.map(value=><button key={value} type="button" className={subject===value?"active":""} onClick={()=>{setSubject(value);setHistoryOpen(false)}}>{value}</button>)}</div></div>}
    {visible.length?<><div className="family-grade-summary"><article className="latest"><span>최근 시험</span><b>{latest.examName}</b><small>{formatDate(latest.examDate)} · {latest.subject}</small></article><article><span>{type==="mock"?"최근 백분위":"최근 원점수"}</span><b>{type==="mock"?(latest.percentile??latest.score??"–"):(latest.score??"–")}<em>{(type==="mock"?(latest.percentile??latest.score):latest.score)!==null?"점":""}</em></b><small>{gradeLabel(latest,isMiddle)}</small></article><article><span>조회 평균</span><b>{average??"–"}<em>{average!==null?"점":""}</em></b><small>{visible.length}회 기준</small></article></div>
      <AcademicTrendChart records={visible} type={type} isMiddle={isMiddle}/>
      <button type="button" className={`family-grade-history-toggle${historyOpen?" open":""}`} aria-expanded={historyOpen} onClick={()=>setHistoryOpen(value=>!value)}><span>전체 기록 보기 <b>{visible.length}</b></span><i>{historyOpen?"접기":"펼치기"} <em>⌄</em></i></button>
      {historyOpen&&<div className="family-academic-list">{visible.map(item=><article key={item.id}><time>{formatShortDate(item.examDate)}</time><div><b>{item.examName}</b><span>{item.subject} · {item.academicYear}년{item.semester?` ${item.semester}학기`:""}</span><small>{recordDetails(item,isMiddle)}</small>{item.note&&<p>{item.note}</p>}</div><strong>{primaryResult(item,type,isMiddle)}</strong></article>)}</div>}</>:<div className="family-grade-empty"><b>아직 등록된 {type==="school"?"내신":"모의고사"} 성적이 없어요.</b><span>선생님이 데스크톱 학생 상세에서 입력하면 이곳에 바로 표시됩니다.</span></div>}
  </section>;
}

function AcademicTrendChart({records,type,isMiddle}:{records:AcademicRecord[];type:RecordType;isMiddle:boolean}){
  const points=[...records].sort((left,right)=>left.examDate.localeCompare(right.examDate)).slice(-8).map(item=>({item,value:type==="mock"?(item.percentile??item.score):item.score})).filter((point):point is {item:AcademicRecord;value:number}=>point.value!==null);
  if(!points.length)return <div className="family-grade-chart empty"><b>추이를 표시할 점수가 없어요.</b><span>원점수나 백분위가 입력되면 그래프가 만들어집니다.</span></div>;
  const width=320,height=150,padX=22,padTop=22,padBottom=34;const plotHeight=height-padTop-padBottom;
  const x=(index:number)=>points.length===1?width/2:padX+(index*(width-padX*2))/(points.length-1);const y=(value:number)=>padTop+((100-Math.max(0,Math.min(100,value)))/100)*plotHeight;
  const line=points.map((point,index)=>`${x(index)},${y(point.value)}`).join(" ");const area=`${x(0)},${height-padBottom} ${line} ${x(points.length-1)},${height-padBottom}`;
  return <figure className="family-grade-chart"><figcaption><div><b>{type==="mock"?"백분위 추이":"원점수 추이"}</b><span>최근 {points.length}회</span></div><small>높을수록 좋아요</small></figcaption><div className="family-grade-chart-canvas">
    <span className="axis top">100</span><span className="axis middle">50</span><span className="axis bottom">0</span>
    <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${type==="mock"?"백분위":"원점수"} 성적 추이 그래프`} preserveAspectRatio="none">
      <defs><linearGradient id={`familyAcademicArea-${type}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#b7447c" stopOpacity=".2"/><stop offset="1" stopColor="#b7447c" stopOpacity="0"/></linearGradient></defs>
      <line className="grid" x1={padX} x2={width-padX} y1={padTop} y2={padTop}/><line className="grid" x1={padX} x2={width-padX} y1={padTop+plotHeight/2} y2={padTop+plotHeight/2}/><line className="grid" x1={padX} x2={width-padX} y1={height-padBottom} y2={height-padBottom}/>
      <polygon className="area" points={area} fill={`url(#familyAcademicArea-${type})`}/><polyline className="line" points={line}/>{points.map((point,index)=><g key={point.item.id}><circle className="dot" cx={x(index)} cy={y(point.value)} r="4"/><text className="value" x={x(index)} y={Math.max(13,y(point.value)-9)} textAnchor="middle">{Math.round(point.value)}</text></g>)}
    </svg><div className="family-grade-chart-labels">{points.map((point,index)=><span key={point.item.id} style={{left:`${(x(index)/width)*100}%`}}><b>{formatChartDate(point.item.examDate)}</b><small>{trendResult(point.item,isMiddle)}</small></span>)}</div>
  </div></figure>;
}
function trendResult(item:AcademicRecord,isMiddle:boolean){if(isMiddle&&item.achievementLevel)return item.achievementLevel;if(item.grade!==null)return `${item.grade}등급`;return item.subject}
function primaryResult(item:AcademicRecord,type:RecordType,isMiddle:boolean){if(type==="school"&&isMiddle)return item.achievementLevel??(item.score!==null?`${Math.round(item.score)}점`:"–");if(item.grade!==null)return `${item.grade}등급`;return item.score!==null?`${Math.round(item.score)}점`:"–"}
function gradeLabel(item:AcademicRecord,isMiddle:boolean){if(isMiddle&&item.achievementLevel)return `성취도 ${item.achievementLevel}`;if(item.grade!==null)return `${item.grade}등급`;return "등급 미입력"}
function recordDetails(item:AcademicRecord,isMiddle:boolean){const values:string[]=[];if(item.score!==null)values.push(`원점수 ${Math.round(item.score)}점`);if(isMiddle&&item.achievementLevel)values.push(`성취도 ${item.achievementLevel}`);if(!isMiddle&&item.grade!==null)values.push(`${item.grade}등급`);if(item.standardScore!==null)values.push(`표준점수 ${Math.round(item.standardScore)}`);if(item.percentile!==null)values.push(`백분위 ${Math.round(item.percentile)}`);if(item.rank!==null)values.push(`석차 ${item.rank}/${item.cohortSize??"–"}`);return values.join(" · ")||"상세 성적 미입력"}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric"}).format(new Date(`${value}T12:00:00+09:00`))}
function formatShortDate(value:string){const date=new Date(`${value}T12:00:00+09:00`);return `${String(date.getMonth()+1).padStart(2,"0")}.${String(date.getDate()).padStart(2,"0")}`}
function formatChartDate(value:string){const date=new Date(`${value}T12:00:00+09:00`);return `${date.getMonth()+1}.${date.getDate()}`}
