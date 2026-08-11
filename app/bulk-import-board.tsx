"use client";

import { useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type ImportRow={studentName:string;school:string;grade:string;phone:string;status:string;className:string;subject:string;room:string;monthlyFee:string};
type ImportResult={rows:number;studentsCreated:number;classesCreated:number;enrollmentsCreated:number};
const headers=["학생이름","학교","학년","학생연락처","상태","클래스","과목","강의실","월수강료"];

export function BulkImportBoard({supabase}:{supabase:SupabaseClient}){
  const input=useRef<HTMLInputElement>(null);
  const[fileName,setFileName]=useState("");
  const[rows,setRows]=useState<ImportRow[]>([]);
  const[errors,setErrors]=useState<string[]>([]);
  const[busy,setBusy]=useState(false);
  const[result,setResult]=useState<ImportResult|null>(null);

  const selectFile=async(file:File)=>{
    setFileName(file.name);setResult(null);
    try{
      const matrix=parseCsv(await file.text());
      if(!matrix.length)throw new Error("빈 CSV 파일입니다.");
      const actualHeaders=matrix[0].map(x=>x.trim());
      const missing=headers.filter(x=>!actualHeaders.includes(x));
      if(missing.length)throw new Error(`필수 열이 없습니다: ${missing.join(", ")}`);
      const index=(name:string)=>actualHeaders.indexOf(name);
      const next=matrix.slice(1).filter(row=>row.some(x=>x.trim())).map(row=>({studentName:row[index("학생이름")]?.trim()??"",school:row[index("학교")]?.trim()??"",grade:row[index("학년")]?.trim()??"",phone:row[index("학생연락처")]?.trim()??"",status:row[index("상태")]?.trim()||"재원",className:row[index("클래스")]?.trim()??"",subject:row[index("과목")]?.trim()??"",room:row[index("강의실")]?.trim()??"",monthlyFee:row[index("월수강료")]?.trim()??""}));
      const issues:string[]=[];
      if(!next.length)issues.push("등록할 데이터 행이 없습니다.");
      if(next.length>1000)issues.push("한 번에 최대 1000행까지 등록할 수 있습니다.");
      next.forEach((r,i)=>{if(!r.studentName)issues.push(`${i+2}행: 학생 이름이 없습니다.`);if(r.className&&!r.subject)issues.push(`${i+2}행: 클래스 과목이 없습니다.`);if(r.monthlyFee&&!/^\d+$/.test(r.monthlyFee.replaceAll(",","")))issues.push(`${i+2}행: 월수강료는 숫자로 입력해 주세요.`);if(r.status&&!['재원','휴원','퇴원','active','paused','completed'].includes(r.status))issues.push(`${i+2}행: 상태는 재원·휴원·퇴원 중 하나여야 합니다.`)});
      setRows(next);setErrors(issues);
    }catch(error){setRows([]);setErrors([error instanceof Error?error.message:"CSV 파일을 읽지 못했습니다."])}
  };
  const submit=async()=>{if(!rows.length||errors.length)return;setBusy(true);setResult(null);const{data,error}=await supabase.rpc("admin_bulk_import_roster",{p_rows:rows,p_file_name:fileName});if(error)setErrors([error.message]);else setResult(data as ImportResult);setBusy(false)};
  return <><div className="page-heading compact"><div><p className="eyebrow">관리자 전용</p><h1>학생·클래스 일괄 등록</h1><p>CSV를 먼저 검증한 뒤 학생, 클래스와 수강 배정을 한 번에 등록합니다.</p></div><button className="secondary-button" onClick={downloadTemplate}>CSV 양식 다운로드</button></div><section className="panel import-guide"><h2>작성 방법</h2><div><span><b>1</b>양식을 내려받아 학생 정보를 입력합니다.</span><span><b>2</b>한 학생이 여러 클래스를 수강하면 학생 정보를 반복해 여러 행으로 작성합니다.</span><span><b>3</b>미리보기의 오류가 없을 때만 최종 등록합니다.</span></div><small>학생 이름은 필수입니다. 클래스가 있으면 과목도 필요하며, 월수강료는 숫자만 입력합니다.</small></section><section className="panel import-upload"><input ref={input} hidden type="file" accept=".csv,text/csv" onChange={e=>{const f=e.target.files?.[0];if(f)void selectFile(f)}}/><button className="primary" onClick={()=>input.current?.click()}>CSV 파일 선택</button><span>{fileName||"선택한 파일이 없습니다."}</span></section>{errors.length>0&&<section className="panel import-errors"><h2>확인이 필요합니다</h2>{errors.slice(0,20).map((x,i)=><p key={i}>{x}</p>)}{errors.length>20&&<small>외 {errors.length-20}건</small>}</section>}{rows.length>0&&<section className="panel import-preview"><header><div><h2>등록 미리보기</h2><p>총 {rows.length}행 · 화면에는 처음 30행을 표시합니다.</p></div><button className="primary" disabled={busy||errors.length>0} onClick={()=>void submit()}>{busy?"등록 중…":"검증한 내용 등록"}</button></header><div className="import-table"><div className="head"><b>학생</b><b>학교·학년</b><b>연락처</b><b>클래스·과목</b><b>월수강료</b></div>{rows.slice(0,30).map((r,i)=><div key={i}><span><b>{r.studentName}</b><small>{r.status}</small></span><span>{[r.school,r.grade].filter(Boolean).join(" · ")||"-"}</span><span>{r.phone||"-"}</span><span>{r.className?<>{r.className}<small>{r.subject}{r.room?` · ${r.room}`:""}</small></>:"미배정"}</span><span>{r.monthlyFee?`${Number(r.monthlyFee.replaceAll(",","")).toLocaleString("ko-KR")}원`:"-"}</span></div>)}</div></section>}{result&&<section className="panel import-result"><h2>일괄 등록 완료</h2><div><b>{result.studentsCreated}명</b><span>신규 학생</span><b>{result.classesCreated}개</b><span>신규 클래스</span><b>{result.enrollmentsCreated}건</b><span>수강 배정</span></div><p>중복 학생과 기존 클래스는 새로 만들지 않고 연결했습니다. 학생 화면을 새로고침하면 결과가 표시됩니다.</p></section>}</>;
}

function parseCsv(text:string){const source=text.replace(/^\ufeff/,"");const rows:string[][]=[];let row:string[]=[];let field="";let quoted=false;for(let i=0;i<source.length;i++){const c=source[i];if(quoted){if(c==='"'&&source[i+1]==='"'){field+='"';i++}else if(c==='"')quoted=false;else field+=c}else if(c==='"')quoted=true;else if(c===','){row.push(field);field=""}else if(c==='\n'){row.push(field.replace(/\r$/,"") );rows.push(row);row=[];field=""}else field+=c}if(field||row.length){row.push(field.replace(/\r$/,"") );rows.push(row)}return rows}
function downloadTemplate(){const sample=[headers,["홍길동","배곧중학교","중2","010-0000-0000","재원","중2 수학 A","수학","A강의실","250000"]];const csv="\ufeff"+sample.map(row=>row.map(v=>`"${v.replaceAll('"','""')}"`).join(",")).join("\r\n");const url=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8"}));const a=document.createElement("a");a.href=url;a.download="한살매_학생클래스_일괄등록_양식.csv";a.click();URL.revokeObjectURL(url)}
