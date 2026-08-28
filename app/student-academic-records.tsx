"use client";

import type { FormEvent } from "react";
import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { appConfirm } from "./app-dialog";

type RecordType = "school" | "mock";
type AcademicRecord = {
  id: string; record_type: RecordType; academic_year: number; school_grade: string | null; semester: number | null;
  exam_date: string; exam_name: string; subject: string; score: number | null;
  grade: number | null; achievement_level: string | null; rank: number | null; cohort_size: number | null;
  school_average: number | null; standard_score: number | null;
  percentile: number | null; note: string | null; created_at: string;
};
type FormValues = {
  academicYear:string; schoolGrade:string; semester:string; examDate:string; examName:string; subject:string;
  score:string; grade:string; achievementLevel:string; rank:string; cohortSize:string; schoolAverage:string;
  standardScore:string; percentile:string; note:string;
};

const currentYear = new Date().getFullYear();
const emptyForm = (type:RecordType,schoolGrade:string):FormValues => ({
  academicYear:String(currentYear), schoolGrade, semester:"1", examDate:new Date().toISOString().slice(0,10),
  examName:type==="school"?"1학기 중간고사":"3월 모의고사", subject:"", score:"", grade:"", achievementLevel:"",
  rank:"", cohortSize:"", schoolAverage:"", standardScore:"", percentile:"", note:"",
});
const numeric = (value:string) => value.trim()==="" ? null : Number(value);
const recordColumns = "id,record_type,academic_year,school_grade,semester,exam_date,exam_name,subject,score,grade,achievement_level,rank,cohort_size,school_average,standard_score,percentile,note,created_at";
const schoolExamNames=["1학기 중간고사","1학기 기말고사","2학기 중간고사","2학기 기말고사","기타"];

function AcademicTrendChart({items,type}:{items:AcademicRecord[];type:RecordType}) {
  const values=items.map(item=>type==="mock"?(item.percentile??item.score):(item.score??null));
  const chartWidth=900;
  const chartHeight=230;
  const plotTop=30;
  const plotBottom=165;
  const xAt=(index:number)=>items.length===1?chartWidth/2:72+(index*(chartWidth-144))/(items.length-1);
  const yAt=(value:number)=>plotBottom-(Math.max(0,Math.min(100,value))/100)*(plotBottom-plotTop);
  const validPoints=values.flatMap((value,index)=>value===null?[]:[{x:xAt(index),y:yAt(value),value,index}]);
  const path=validPoints.map((point,index)=>`${index===0?"M":"L"} ${point.x} ${point.y}`).join(" ");

  return <div className="academic-line-chart">
    <svg viewBox={`0 0 ${chartWidth} ${chartHeight}`} role="img" aria-label={`${type==="mock"?"백분위 우선":"원점수 기준"} 최근 성적 선 그래프`} preserveAspectRatio="none">
      {[100,75,50,25,0].map(value=>{const y=yAt(value);return <g key={value} className="academic-chart-grid"><line x1="52" x2={chartWidth-28} y1={y} y2={y}/><text x="42" y={y+4} textAnchor="end">{value}</text></g>})}
      {validPoints.length>1?<path className="academic-chart-area" d={`${path} L ${validPoints.at(-1)?.x} ${plotBottom} L ${validPoints[0].x} ${plotBottom} Z`}/>:null}
      {path?<path className="academic-chart-line" d={path}/>:null}
      {validPoints.map(point=><g key={items[point.index].id} className="academic-chart-point"><circle cx={point.x} cy={point.y} r="8"/><circle cx={point.x} cy={point.y} r="3"/><text x={point.x} y={point.y-14} textAnchor="middle">{point.value}점</text></g>)}
      {items.map((item,index)=><g key={item.id} className="academic-chart-label"><text x={xAt(index)} y="194" textAnchor="middle">{item.exam_name}</text><text x={xAt(index)} y="214" textAnchor="middle">{item.subject} · {item.exam_date.slice(5).replace("-",".")}</text></g>)}
    </svg>
  </div>;
}

export function StudentAcademicRecords({supabase,studentId,studentGrade}:{supabase:SupabaseClient;studentId:string;studentGrade:string}) {
  const normalizedStudentGrade=studentGrade.replace(/\s+/g,"");
  const isMiddleSchool = /^(초6|중[1-3])$/.test(normalizedStudentGrade);
  const schoolGradeOptions=isMiddleSchool?["초6","중1","중2","중3"]:["고1","고2","고3","재수","검정고시"];
  const initialSchoolGrade=schoolGradeOptions.includes(normalizedStudentGrade)?normalizedStudentGrade:schoolGradeOptions[0];
  const [type,setType]=useState<RecordType>("school");
  const [records,setRecords]=useState<AcademicRecord[]>([]);
  const [loading,setLoading]=useState(true);
  const [editorOpen,setEditorOpen]=useState(false);
  const [editingId,setEditingId]=useState<string|null>(null);
  const [form,setForm]=useState<FormValues>(()=>emptyForm("school",initialSchoolGrade));
  const [saving,setSaving]=useState(false);
  const [message,setMessage]=useState("");
  const [deleteId]=useState<string|null>(null);
  const [year,setYear]=useState("all");
  const [subject,setSubject]=useState("all");

  useEffect(()=>{
    let active=true;
    void supabase.from("student_academic_records").select(recordColumns).eq("student_id",studentId).order("exam_date",{ascending:false}).order("created_at",{ascending:false}).then(({data,error})=>{
      if(!active)return;
      setRecords((data??[]) as AcademicRecord[]);
      setMessage(error?"성적 기록을 불러오지 못했습니다.":"");
      setLoading(false);
    });
    return()=>{active=false;};
  },[studentId,supabase]);

  const typed=useMemo(()=>records.filter(item=>item.record_type===type),[records,type]);
  const years=useMemo(()=>Array.from(new Set(typed.map(item=>item.academic_year))).sort((a,b)=>b-a),[typed]);
  const subjects=useMemo(()=>Array.from(new Set(typed.map(item=>item.subject))).sort(),[typed]);
  const visible=useMemo(()=>typed.filter(item=>(year==="all"||item.academic_year===Number(year))&&(subject==="all"||item.subject===subject)),[typed,year,subject]);
  const trend=visible.slice(0,6).toReversed();
  const latest=visible[0];

  const switchType=(next:RecordType)=>{setType(next);setYear("all");setSubject("all");setDeleteId(null);setEditorOpen(false);};
  const update=(key:keyof FormValues,value:string)=>setForm(current=>({...current,[key]:value}));
  const openNew=()=>{setEditingId(null);setForm(emptyForm(type,initialSchoolGrade));setMessage("");setEditorOpen(true);};
  const openEdit=(item:AcademicRecord)=>{
    setEditingId(item.id);setDeleteId(null);setMessage("");
    setForm({academicYear:String(item.academic_year),schoolGrade:item.school_grade??initialSchoolGrade,semester:String(item.semester??1),examDate:item.exam_date,examName:item.exam_name,subject:item.subject,score:String(item.score??""),grade:String(item.grade??""),achievementLevel:item.achievement_level??"",rank:String(item.rank??""),cohortSize:String(item.cohort_size??""),schoolAverage:String(item.school_average??""),standardScore:String(item.standard_score??""),percentile:String(item.percentile??""),note:item.note??""});
    setEditorOpen(true);
  };
  const save=async(event:FormEvent)=>{
    event.preventDefault();setSaving(true);setMessage("");
    const payload={student_id:studentId,record_type:type,academic_year:Number(form.academicYear),school_grade:form.schoolGrade,semester:type==="school"?Number(form.semester):null,exam_date:form.examDate,exam_name:form.examName.trim(),subject:form.subject.trim(),score:numeric(form.score),grade:isMiddleSchool?null:numeric(form.grade),achievement_level:isMiddleSchool&&type==="school"?(form.achievementLevel||null):null,rank:type==="school"?numeric(form.rank):null,cohort_size:type==="school"?numeric(form.cohortSize):null,school_average:type==="school"?numeric(form.schoolAverage):null,standard_score:type==="mock"?numeric(form.standardScore):null,percentile:type==="mock"?numeric(form.percentile):null,note:form.note.trim()||null,updated_at:new Date().toISOString()};
    const query=editingId?supabase.from("student_academic_records").update(payload).eq("id",editingId):supabase.from("student_academic_records").insert(payload);
    const {data,error}=await query.select(recordColumns).single();
    setSaving(false);
    if(error){setMessage(isMiddleSchool?"입력값을 확인해 주세요. 점수는 0~100, 성취도는 A~E로 입력합니다.":type==="school"?"입력값을 확인해 주세요. 점수는 0~100, 내신 등급은 1~5로 입력합니다.":"입력값을 확인해 주세요. 점수·백분위는 0~100, 모의고사·수능 등급은 1~9로 입력합니다.");return;}
    setRecords(current=>[data as AcademicRecord,...current.filter(item=>item.id!==(data as AcademicRecord).id)].sort((a,b)=>b.exam_date.localeCompare(a.exam_date)||b.created_at.localeCompare(a.created_at)));
    setEditorOpen(false);setMessage(editingId?"성적을 수정했습니다.":"성적을 등록했습니다.");
  };
  const remove=async(id:string)=>{
    setSaving(true);setMessage("");
    const {error}=await supabase.from("student_academic_records").delete().eq("id",id);
    setSaving(false);
    if(error){setMessage("성적 기록을 삭제하지 못했습니다.");return;}
    setRecords(current=>current.filter(item=>item.id!==id));setDeleteId(null);setMessage("성적 기록을 삭제했습니다.");
  };
  const setDeleteId=async(id:string|null)=>{
    if(!id||saving)return;
    const item=records.find(record=>record.id===id);
    if(!item)return;
    const confirmed=await appConfirm({eyebrow:"성적 기록 삭제",title:`${item.exam_name} · ${item.subject} 성적을 삭제할까요?`,notice:"삭제한 성적 기록은 복구할 수 없습니다.",confirmLabel:"성적 삭제",tone:"danger"});
    if(confirmed)await remove(id);
  };

  return <section className="academic-records">
    <div className="student-tab-intro academic-heading"><div><h3>성적 관리</h3><p>{isMiddleSchool?"학교 내신 점수와 A~E 성취도를 관리합니다.":"내신 5등급과 모의고사·수능 9등급 성적을 구분해 관리합니다."}</p></div><button type="button" className="academic-add-button" onClick={openNew}>성적 등록</button></div>
    <div className="academic-toolbar"><nav className={isMiddleSchool?"single":undefined} aria-label="성적 종류">{isMiddleSchool?<button type="button" className="active" disabled>내신 성적</button>:([['school','내신 성적'],['mock','모의고사·수능']] as [RecordType,string][]).map(([id,label])=><button type="button" key={id} className={type===id?"active":""} onClick={()=>switchType(id)}>{label}</button>)}</nav><div className="academic-filters"><label><span>연도</span><select value={year} onChange={e=>setYear(e.target.value)}><option value="all">전체</option>{years.map(value=><option key={value}>{value}</option>)}</select></label><label><span>과목</span><select value={subject} onChange={e=>setSubject(e.target.value)}><option value="all">전체</option>{subjects.map(value=><option key={value}>{value}</option>)}</select></label></div></div>
    {message?<p className="academic-message">{message}</p>:null}
    {editorOpen?<form className="academic-editor" onSubmit={save}><div className="academic-editor-heading"><div><b>{editingId?"성적 수정":"새 성적 등록"}</b><span>{type==="school"?(isMiddleSchool?"학교 내신 점수와 A~E 성취도를 입력합니다.":"학교 내신 점수와 1~5등급을 입력합니다."):"모의고사·수능 점수와 1~9등급을 입력합니다."}</span></div><button type="button" aria-label="등록 창 닫기" onClick={()=>setEditorOpen(false)}>×</button></div><div className="academic-form-grid">
      <label><span>연도 *</span><input type="number" min="2000" max="2100" required value={form.academicYear} onChange={e=>update("academicYear",e.target.value)}/></label>
      <label><span>학년 *</span><select required value={form.schoolGrade} onChange={e=>update("schoolGrade",e.target.value)}>{schoolGradeOptions.map(value=><option key={value}>{value}</option>)}</select></label>
      {type==="school"?<label><span>학기 *</span><select value={form.semester} onChange={e=>update("semester",e.target.value)}><option value="1">1학기</option><option value="2">2학기</option></select></label>:null}
      <label className="mobile-wide"><span>{type==="school"?"시험일":"시행일"} *</span><span className="academic-date-field"><input type="date" required value={form.examDate} onChange={e=>update("examDate",e.target.value)}/></span></label>
      <label className="mobile-wide"><span>시험명 *</span>{type==="school"?<select required value={form.examName} onChange={e=>update("examName",e.target.value)}>{!schoolExamNames.includes(form.examName)&&<option value={form.examName}>{form.examName}</option>}{schoolExamNames.map(value=><option key={value}>{value}</option>)}</select>:<input required value={form.examName} onChange={e=>update("examName",e.target.value)} placeholder="6월 모의고사"/>}</label>
      <label><span>과목 *</span><input required value={form.subject} onChange={e=>update("subject",e.target.value)} placeholder="과목을 입력하세요"/></label>
      <label><span>원점수</span><input type="number" min="0" max="100" step="0.01" value={form.score} onChange={e=>update("score",e.target.value)}/></label>
      {isMiddleSchool&&type==="school"?<label><span>성취도</span><select value={form.achievementLevel} onChange={e=>update("achievementLevel",e.target.value)}><option value="">선택</option>{["A","B","C","D","E"].map(value=><option key={value}>{value}</option>)}</select></label>:<label><span>{type==="school"?"내신 등급":"모의고사·수능 등급"}</span><input type="number" min="1" max={type==="school"?5:9} value={form.grade} onChange={e=>update("grade",e.target.value)}/></label>}
      {type==="school"?<><label><span>석차</span><input type="number" min="1" value={form.rank} onChange={e=>update("rank",e.target.value)}/></label><label><span>재적 인원</span><input type="number" min="1" value={form.cohortSize} onChange={e=>update("cohortSize",e.target.value)}/></label><label><span>학교 평균</span><input type="number" min="0" max="100" step="0.01" value={form.schoolAverage} onChange={e=>update("schoolAverage",e.target.value)}/></label></>:<><label><span>표준점수</span><input type="number" min="0" step="0.01" value={form.standardScore} onChange={e=>update("standardScore",e.target.value)}/></label><label><span>백분위</span><input type="number" min="0" max="100" step="0.01" value={form.percentile} onChange={e=>update("percentile",e.target.value)}/></label></>}
      <label className="wide"><span>메모</span><textarea rows={2} value={form.note} onChange={e=>update("note",e.target.value)} placeholder="시험 범위, 특이사항 등을 기록하세요."/></label>
    </div><div className="academic-editor-actions"><small>{isMiddleSchool?"원점수·성취도·석차 중 하나 이상 입력해 주세요.":"원점수·등급·석차 중 하나 이상 입력해 주세요."}</small><div><button type="button" onClick={()=>setEditorOpen(false)}>취소</button><button className="academic-primary" disabled={saving}>{saving?"저장 중…":"저장"}</button></div></div></form>:null}
    {!loading&&visible.length?<><div className="academic-summary"><article><span>최근 시험</span><b>{latest.exam_name}</b><small>{latest.exam_date}</small></article><article><span>최근 원점수</span><b>{latest.score??"-"}<small>{latest.score!==null?"점":""}</small></b><small>{latest.subject}</small></article><article><span>{latest.achievement_level?"최근 성취도":"최근 등급"}</span><b>{latest.achievement_level??latest.grade??"-"}<small>{latest.grade!==null?"등급":""}</small></b><small>{visible.length}건 기록</small></article></div><section className="academic-trend"><header><div><b>최근 성적 변화</b><small>시험별 점수 흐름을 한눈에 확인합니다.</small></div><span>{type==="mock"?"백분위 우선":"원점수 기준"}</span></header><AcademicTrendChart items={trend} type={type}/></section><div className="academic-list">{visible.map(item=><article key={item.id}><div><span>{item.academic_year}년{item.semester?` · ${item.semester}학기`:""} · {item.exam_date}</span><b>{item.exam_name} · {item.subject}</b><p>{item.score!==null?`원점수 ${item.score}`:""}{item.standard_score!==null?` · 표준점수 ${item.standard_score}`:""}{item.percentile!==null?` · 백분위 ${item.percentile}`:""}{item.achievement_level?` · 성취도 ${item.achievement_level}`:""}{item.grade!==null?` · ${item.grade}등급`:""}{item.rank!==null?` · ${item.rank}/${item.cohort_size??"-"}등`:""}{item.school_average!==null?` · 학교 평균 ${item.school_average}`:""}</p>{item.note?<small>{item.note}</small>:null}</div><footer><button type="button" onClick={()=>openEdit(item)}>수정</button><button type="button" className="danger" onClick={()=>setDeleteId(item.id)}>삭제</button></footer>{deleteId===item.id?<div className="academic-delete"><span>이 성적 기록을 삭제할까요?</span><div><button type="button" onClick={()=>setDeleteId(null)}>취소</button><button type="button" className="danger-fill" disabled={saving} onClick={()=>void remove(item.id)}>삭제</button></div></div>:null}</article>)}</div></>:loading?<p className="academic-empty">성적 기록을 불러오는 중이에요…</p>:<p className="academic-empty">아직 등록된 {type==="school"?"내신":"모의고사·수능"} 성적이 없습니다.</p>}
  </section>;
}
