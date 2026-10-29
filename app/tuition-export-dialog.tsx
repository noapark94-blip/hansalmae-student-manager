"use client";
import {useEffect,useRef,useState} from 'react';
import {createPortal} from 'react-dom';
import type {SupabaseClient} from '@supabase/supabase-js';
import {amounts,defaultColumns,exportColumns,exportValue,koreaDate,matchesExport,monthsBetween,paymentRows,statusLabels,type ColumnKey,type ExportCharge,type ExportEntry,type ExportFilters} from './tuition-export-model';
import styles from './tuition-export.module.css';
const emptyFilters:ExportFilters={query:'',school:'',grade:'',subject:'',status:''};
const won=(n:number)=>n.toLocaleString('ko-KR')+'원';
export function TuitionExportDialog({month,rows,initialStudentIds,supabase,onClose}:{month:string;rows:ExportCharge[];initialStudentIds:string[];supabase:SupabaseClient;onClose:()=>void}){
 const dialog=useRef<HTMLDialogElement>(null),request=useRef(0);
 const [start,setStart]=useState(month),[end,setEnd]=useState(month),[loadedRange,setLoadedRange]=useState([month,month]);
 const [entries,setEntries]=useState<ExportEntry[]>(()=>rows.map(r=>({...r,month})));
 const [scope,setScope]=useState<'current'|'all'>('current');
 const [filters,setFilters]=useState<ExportFilters>(emptyFilters);
 const [excluded,setExcluded]=useState<Set<string>>(()=>new Set());
 const [columns,setColumns]=useState<ColumnKey[]>(defaultColumns);
 const [loading,setLoading]=useState(false),[saving,setSaving]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 useEffect(()=>{const node=dialog.current;node?.showModal();return()=>{request.current++;node?.close();};},[]);
 const dirty=start!==loadedRange[0]||end!==loadedRange[1];
 const base=entries.filter(r=>scope==='all'||initialStudentIds.includes(r.studentId));
 const matches=base.filter(r=>matchesExport(r,filters));
 const students=[...new Map(matches.map(r=>[r.studentId,r])).values()].sort((a,b)=>a.studentName.localeCompare(b.studentName,'ko'));
 const selected=matches.filter(r=>!excluded.has(r.studentId));
 const selectedCount=new Set(selected.map(r=>r.studentId)).size;
 const shownColumns=exportColumns.filter(c=>columns.includes(c[0]));
 const totals=selected.reduce((a,r)=>{const x=amounts(r);return {paid:a.paid+x.paid,balance:a.balance+x.balance};},{paid:0,balance:0});
 const preview=selected.flatMap(r=>paymentRows(r).map((p,i)=>({row:r,p,first:i===0}))).slice(0,30);
 const busy=loading||saving;
 async function loadRange(){
  const months=monthsBetween(start,end);if(!months.length){setError('시작월과 종료월을 확인해 주세요. 한 번에 최대 24개월까지 선택할 수 있습니다.');return;}
  const id=++request.current;setLoading(true);setError('');setMessage('');
  try{
   const result:ExportEntry[]=[];
   for(const m of months){const {data,error:failure}=await supabase.rpc('tuition_board',{p_month:`${m}-01`});
    if(id!==request.current)return;
    if(failure||!data?.isStaff||!Array.isArray(data.items))throw new Error('원비 자료를 불러오지 못했습니다. 권한과 연결 상태를 확인한 뒤 다시 시도해 주세요.');
    result.push(...data.items.map((r:ExportCharge)=>({...r,month:m})));
   }
   if(id===request.current){setEntries(result);setLoadedRange([start,end]);}
  }catch(e){if(id===request.current)setError(e instanceof Error?e.message:'자료를 불러오지 못했습니다.');}
  finally{if(id===request.current)setLoading(false);}
 }
 function toggle(id:string){setExcluded(old=>{const next=new Set(old);if(next.has(id))next.delete(id);else next.add(id);return next;});setMessage('');}
 async function download(){
  if(busy||dirty||!selected.length||!columns.length||error)return;
  setSaving(true);setMessage('');
  try{const {tuitionExcel}=await import('./tuition-export-excel');
   const url=URL.createObjectURL(new Blob([tuitionExcel(selected,columns)],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));
   const a=document.createElement('a');a.href=url;a.download=`원비목록_${loadedRange[0]}${loadedRange[1]!==loadedRange[0]?'_'+loadedRange[1]:''}.xlsx`;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);
   setMessage('선택한 항목과 학생으로 엑셀 파일을 저장했습니다.');
  }catch{setMessage('파일을 만들지 못했습니다. 다시 시도해 주세요.');}finally{setSaving(false);}
 }
 const options=(key:'school'|'grade'|'subject')=>[...new Set(base.flatMap(r=>key==='subject'?r.subjects??[]:[key==='school'?r.school||'학교 미등록':r.grade||'학년 미등록']))].sort((a,b)=>a.localeCompare(b,'ko',{numeric:true}));
 return createPortal(<dialog ref={dialog} className={styles.dialog} aria-labelledby="tuition-export-title" onCancel={e=>{e.preventDefault();onClose();}}>
  <header><div><small>원비 자료 저장</small><h2 id="tuition-export-title">엑셀 내보내기</h2><p>필요한 항목과 학생만 골라 월별로 저장하세요.</p></div><button type="button" aria-label="엑셀 내보내기 닫기" onClick={onClose}>×</button></header>
  <div className={styles.body}>
   <fieldset disabled={busy} className={styles.period}><legend>1. 내보낼 기간</legend><label>시작월<input type="month" value={start} onChange={e=>setStart(e.target.value)}/></label><span>~</span><label>종료월<input type="month" value={end} onChange={e=>setEnd(e.target.value)}/></label><button type="button" onClick={()=>void loadRange()}>{loading?'불러오는 중…':'기간 적용'}</button></fieldset>
   {dirty&&<p className={styles.notice}>기간을 변경했습니다. ‘기간 적용’을 눌러 목록을 갱신해 주세요.</p>}
   {error&&<p role="alert" className={styles.error}>{error}</p>}
   <fieldset disabled={busy}><legend>2. 포함할 항목 <small>{columns.length}개 선택</small></legend><div className={styles.actions}><button type="button" onClick={()=>setColumns(exportColumns.map(c=>c[0]))}>전체 선택</button><button type="button" onClick={()=>setColumns([])}>전체 해제</button><button type="button" onClick={()=>setColumns(defaultColumns)}>기본 항목</button></div><div className={styles.columns}>{exportColumns.map(([key,label])=><label key={key}><input type="checkbox" checked={columns.includes(key)} onChange={()=>setColumns(old=>old.includes(key)?old.filter(k=>k!==key):[...old,key])}/>{label}</label>)}</div></fieldset>
   <fieldset disabled={busy||dirty}><legend>3. 학생 선택 <small>{selectedCount}명 · {selected.length}건</small></legend>
    <div className={styles.tabs}><button type="button" aria-pressed={scope==='current'} onClick={()=>setScope('current')}>현재 화면의 학생 {initialStudentIds.length}명</button><button type="button" aria-pressed={scope==='all'} onClick={()=>setScope('all')}>기간 내 전체 학생</button></div>
    <p className={styles.help}>학교·학년은 현재 등록 정보입니다. 조건에 맞는 월별 기록만 저장하며, 학생 제외는 모든 선택 월에 적용됩니다.</p>
    <div className={styles.filters}>{(['school','grade','subject'] as const).map((key,i)=><label key={key}>{['학교','학년','과목'][i]}<select value={filters[key]} onChange={e=>setFilters(f=>({...f,[key]:e.target.value}))}><option value="">전체</option>{options(key).map(v=><option key={v}>{v}</option>)}</select></label>)}<label>납부 상태<select value={filters.status} onChange={e=>setFilters(f=>({...f,status:e.target.value}))}><option value="">전체</option>{Object.entries(statusLabels).map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label></div>
    <div className={styles.search}><input type="search" aria-label="내보낼 학생 검색" placeholder="이름·학교·학년·반·비고 검색" value={filters.query} onChange={e=>setFilters(f=>({...f,query:e.target.value}))}/><button type="button" onClick={()=>{setFilters(emptyFilters);setExcluded(new Set());}}>선택 초기화</button></div>
    <div className={styles.actions}><b>검색 결과 {students.length}명</b><button type="button" onClick={()=>setExcluded(old=>new Set([...old].filter(id=>!students.some(s=>s.studentId===id))))}>검색 결과 전체 선택</button><button type="button" onClick={()=>setExcluded(old=>new Set([...old,...students.map(s=>s.studentId)]))}>검색 결과 전체 해제</button></div>
    <div className={styles.students}>{students.map(r=><label key={r.studentId}><input type="checkbox" checked={!excluded.has(r.studentId)} onChange={()=>toggle(r.studentId)}/><span><b>{r.studentName}</b><small>{r.school||'학교 미등록'} · {r.grade||'학년 미등록'}</small></span></label>)}{!students.length&&<p>조건에 맞는 학생이 없습니다.</p>}</div>
   </fieldset>
   <section aria-label="엑셀 미리보기"><div className={styles.summary}><h3>저장 미리보기</h3><span>납부 {won(totals.paid)} · 미납 {won(totals.balance)}</span></div><p className={styles.help}>선택한 학생 기준 합계입니다. 면제액은 미납에서 제외합니다. 분할 납부는 건별로 표시하며 원비·면제·미납은 첫 행에만 표시합니다.</p><div className={styles.preview}><table><thead><tr><th>귀속월</th>{shownColumns.map(([k,l])=><th key={k}>{l}</th>)}</tr></thead><tbody>{preview.map(({row,p,first},i)=><tr key={`${row.id}:${i}`}><td>{row.month}</td>{shownColumns.map(([k])=>{const v=exportValue(row,k,p,first);return <td key={k}>{k==='date'?(p?koreaDate(p.paidAt):'—'):typeof v==='number'?v.toLocaleString('ko-KR'):v??'—'}</td>;})}</tr>)}</tbody></table></div><p className={styles.help}>미리보기는 최대 30행입니다. 파일에는 선택한 기록 전체가 월별 시트로 저장됩니다.</p></section>
   {message&&<p role="status" className={styles.notice}>{message}</p>}
  </div><footer><span>학생 {selectedCount}명 · 항목 {columns.length}개</span><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.primary} disabled={busy||dirty||!!error||!selected.length||!columns.length} onClick={()=>void download()}>{saving?'파일 준비 중…':`선택한 ${selectedCount}명 엑셀 저장`}</button></footer>
 </dialog>,document.body);
}
