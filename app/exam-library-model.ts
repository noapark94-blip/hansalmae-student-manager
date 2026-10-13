export type ExamQuestion = { sharedKey?:string; sharedPassage?:string; id:string; number:string; passage:string; prompt:string; choices:string; answer:string; explanation:string; diagram:string };
export type ExamDraft = { title:string; subject:string; school:string; grade:string; year:number; term:string; exam_kind:string; description:string; questions:ExamQuestion[] };
export type ExamRecord = ExamDraft & { id:string; owner_id:string; version:number; updated_at:string };
export type ExamSummary = Omit<ExamRecord,"questions"> & { question_count:number; content_bytes:number };
export const newQuestion = (number=1):ExamQuestion => ({id:crypto.randomUUID(),number:String(number),passage:"",prompt:"",choices:"",answer:"",explanation:"",diagram:""});
export const newExam = ():ExamDraft => ({title:"",subject:"영어",school:"",grade:"고2",year:new Date().getFullYear(),term:"1학기",exam_kind:"중간고사",description:"",questions:[newQuestion()]});
export type ExamParseResult={questions:ExamQuestion[];warnings:string[]};
export function parseExamText(text:string):ExamParseResult{
 const normalized=text.replace(/\r\n?/g,"\n").replace(/\\([.~()[\]<>_])/g,"$1").replace(/<\/?u>/gi,"__").replace(/<\/?(?:b|strong)>/gi,"**");
 const lines=normalized.split("\n");const questions:ExamQuestion[]=[];const warnings:string[]=[];
 const commons:{first:number;last:number;lines:string[];key:string}[]=[];
 const preamble:string[]=[];let common:typeof commons[number]|null=null;let current:ExamQuestion|null=null;let section:"passage"|"choices"|"answer"|"explanation"="passage";
 const append=(key:"passage"|"choices"|"answer"|"explanation",value:string)=>{if(!current)return;current[key]+=(current[key]?"\n":"")+value;};
 for(const original of lines){
  const line=original.replace(/^\s*#{1,6}\s*/,"").trimEnd();
  if(/^\s*(?:[-*_]\s*){3,}$/.test(line))continue;
  const range=line.match(/^\s*\[?\s*(\d{1,3})\s*[~～–—-]\s*(\d{1,3})\s*\]?\s*[.)．]?\s*(.*)$/);
  if(range&&Number(range[1])>=1&&Number(range[2])>=Number(range[1])&&Number(range[2])<=200){common={first:Number(range[1]),last:Number(range[2]),lines:[],key:crypto.randomUUID()};commons.push(common);current=null;continue;}
  const numbered=line.match(/^\s*(서술형|주관식)?\s*[\[(]?\s*(\d{1,3})\s*(?:[.)．\]]|번[.:]?)\s+(.+)$/);
  if(numbered&&Number(numbered[2])>=1&&Number(numbered[2])<=200){
   current=newQuestion(questions.length+1);current.number=(numbered[1]?numbered[1]+" ":"")+numbered[2];questions.push(current);common=null;section="passage";
   const header=numbered[3].trim();if(numbered[1]||/[?？]|(?:것은|고르|답하|쓰시오|적으시오|완성|문장|윗글|다음 글|밑줄|빈칸|서술|설명하|선택하)/.test(header))current.prompt=header;else current.passage=header;
   continue;
  }
  if(common){common.lines.push(line);continue;}
  if(!current){if(line.trim())preamble.push(line);continue;}
  const explicit=line.match(/^\s*(?:\*\*)?[\[<〈【]?\s*(지문|본문|선지|보기|정답|답|해설|해석)\s*[\]>〉】]?\s*(?:\*\*)?\s*[:：]\s*(.*)$/);
  if(explicit){const label=explicit[1];section=label==="지문"||label==="본문"?"passage":label==="선지"||label==="보기"?"choices":label==="정답"||label==="답"?"answer":"explanation";append(section,explicit[2]);continue;}
  if(/^\s*(?:\*\*)?(?:정답|답|해설|해석)(?:\*\*)?\s*$/.test(line)){section=/정답|답/.test(line)?"answer":"explanation";continue;}
  if(!/밑줄 친 문장.*어법상 옳은 것은|밑줄 친 부분.*(?:어법|쓰임)/.test(current.prompt)&&/[①②③④⑤⑥⑦⑧⑨⑩]/.test(line)&&(/^\s*[①②③④⑤⑥⑦⑧⑨⑩]/.test(line)||section==="choices")){
   section="choices";append("choices",line.trim().replace(/\s*([①②③④⑤⑥⑦⑧⑨⑩])/g,"\n$1").trim());continue;
  }
  if(/^\s*\|/.test(line)||/^\s*<(?:A|B|C)>/.test(line))warnings.push(current.number+"번: 표·도식 또는 구획 표시를 확인해 주세요.");
  if(/[□■▢⬜]/.test(line))warnings.push(current.number+"번: 빈칸·도식 배치를 확인해 주세요.");
  append(section,line);
 }
 if(!questions.length){const q=newQuestion();q.passage=preamble.join("\n").trim();questions.push(q);}
 else if(preamble.length){warnings.push("문항 앞의 안내문은 첫 문항의 본문에 남겼습니다. 시험 안내인지 공통지문인지 확인해 주세요.");questions[0].passage=[preamble.join("\n"),questions[0].passage].filter(Boolean).join("\n\n");}
 for(const group of commons){const body=group.lines.join("\n").trim();const targets=questions.filter(q=>!/^서술형|^주관식/.test(q.number)&&Number(q.number)>=group.first&&Number(q.number)<=group.last);if(!body||!targets.length){warnings.push(group.first+"~"+group.last+"번 공통지문의 내용과 문항을 확인해 주세요.");continue;}for(const q of targets){q.sharedKey=group.key;q.sharedPassage=body;q.passage=[body,q.passage].filter(Boolean).join("\n\n");}if(targets.length!==group.last-group.first+1)warnings.push(group.first+"~"+group.last+"번 중 빠진 문항이 있는지 확인해 주세요.");}
 for(const q of questions){for(const key of ["passage","choices","answer","explanation"] as const)q[key]=q[key].trim();if(!q.prompt)warnings.push(q.number+"번: 발문을 확인해 주세요.");if(q.choices){const marks=q.choices.match(/[①②③④⑤⑥⑦⑧⑨⑩]/g)??[];if(marks.length<5||new Set(marks).size!==marks.length)warnings.push(q.number+"번: 선지 개수·번호를 확인해 주세요.");}}
 if(new Set(questions.map(q=>q.number)).size!==questions.length)warnings.push("중복된 문항 번호가 있습니다. 원본 번호를 확인해 주세요.");
 if(questions.length>200)warnings.push("문항은 한 시험당 200개까지 저장할 수 있습니다.");
 return {questions,warnings:Array.from(new Set(warnings))};
}
export function splitExamText(text:string):ExamQuestion[]{return parseExamText(text).questions;}
export function inferExamMetadata(text:string):Partial<ExamDraft>{
  const result:Partial<ExamDraft>={};const school=text.match(/([가-힣]{2,12}(?:고등학교|중학교|고교))/);if(school)result.school=school[1];const year=text.match(/\b(20\d{2})\s*년/);if(year)result.year=Number(year[1]);const term=text.match(/([12])\s*학기/);if(term)result.term=term[1]+"학기";if(/기말/.test(text))result.exam_kind="기말고사";else if(/중간/.test(text))result.exam_kind="중간고사";const grade=text.match(/([123])\s*학년/);if(grade&&school)result.grade=(school[1].includes("중학교")?"중":"고")+grade[1];return result;
}
export function safeDiagram(value:string){return /^data:image\/(?:jpeg|png);base64,[A-Za-z0-9+/=]+$/.test(value)&&value.length<=450000;}
export function validateExam(draft:ExamDraft):string{
  if(!draft.title.trim()||!draft.school.trim())return "시험명과 학교를 입력해 주세요.";
  if(draft.year<2000||draft.year>2100)return "연도를 확인해 주세요.";
  if(!draft.questions.length||draft.questions.length>200)return "문항은 1~200개까지 저장할 수 있습니다.";
  if(draft.questions.some(q=>!q.passage.trim()&&!q.prompt.trim()))return "빈 문항을 삭제하거나 내용을 입력해 주세요.";
  if(draft.questions.some(q=>q.diagram&&!safeDiagram(q.diagram)))return "도형 이미지를 다시 첨부해 주세요.";
  if(new TextEncoder().encode(JSON.stringify(draft)).length>2000000)return "자료가 2MB를 넘습니다. 시험을 나누거나 도형을 줄여 주세요.";
  return "";
}
export type TextPart={text:string;bold?:boolean;underline?:boolean};
export function formattedParts(text:string):TextPart[]{return text.split(/(\*\*[^*\n]+\*\*|__[^_\n]+__)/g).filter(Boolean).map(part=>part.startsWith("**")&&part.endsWith("**")?{text:part.slice(2,-2),bold:true}:part.startsWith("__")&&part.endsWith("__")?{text:part.slice(2,-2),underline:true}:{text:part});}
export function escapeHtml(text:string){return text.replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]!));}
export function questionHtml(q:ExamQuestion,index:number,answers:boolean){const format=(s:string)=>formattedParts(s).map(p=>p.bold?`<strong>${escapeHtml(p.text)}</strong>`:p.underline?`<u>${escapeHtml(p.text)}</u>`:escapeHtml(p.text)).join("");return `<article><h2>${escapeHtml(q.number||String(index+1))}. ${format(q.prompt)}</h2>${q.passage?`<div class="passage">${format(q.passage)}</div>`:""}${q.diagram&&safeDiagram(q.diagram)?`<img class="diagram" src="${q.diagram}" alt="문제 도형">`:""}${q.choices?`<div class="choices">${format(q.choices)}</div>`:""}${answers?`<div class="answer"><b>정답</b> ${format(q.answer)}${q.explanation?`\n<b>해설</b> ${format(q.explanation)}`:""}</div>`:""}</article>`;}

export function sharedPassage(q:ExamQuestion){return q.sharedKey?(q.sharedPassage??q.passage):"";}
export function questionPassage(q:ExamQuestion){const common=sharedPassage(q);return common&&q.passage.startsWith(common)?q.passage.slice(common.length).trim():q.passage;}
export function commonQuestionIndices(questions:ExamQuestion[],question:ExamQuestion){return question.sharedKey?questions.flatMap((q,i)=>q.sharedKey===question.sharedKey&&sharedPassage(q)===sharedPassage(question)?[i]:[]):[];}
export function examQuestionsHtml(questions:ExamQuestion[],answers:boolean){return questions.map((q,i)=>{const group=commonQuestionIndices(questions,q);const common=group[0]===i&&sharedPassage(q)?`<article><h2>${group.map(index=>escapeHtml(questions[index].number)).join("·")}번 공통지문</h2><div class="passage">${formattedParts(sharedPassage(q)).map(p=>p.bold?`<strong>${escapeHtml(p.text)}</strong>`:p.underline?`<u>${escapeHtml(p.text)}</u>`:escapeHtml(p.text)).join("")}</div></article>`:"";return common+questionHtml({...q,passage:q.sharedKey?questionPassage(q):q.passage},i,answers);}).join("");}
export function examMarkdown(exam:ExamDraft,questions:ExamQuestion[],answers:boolean){return ["# "+exam.title,[exam.subject,exam.school,exam.grade,String(exam.year),exam.term,exam.exam_kind].filter(Boolean).join(" · "),...questions.map((q,i)=>{const group=commonQuestionIndices(questions,q);const common=group[0]===i&&sharedPassage(q)?`## [${[questions[group[0]].number,questions[group[group.length-1]].number].join("~")}] 다음 글을 읽고 물음에 답하시오.\n\n${sharedPassage(q)}\n\n`:"";return common+`## ${q.number||i+1}. ${q.prompt}\n\n${q.sharedKey?questionPassage(q):q.passage}\n\n${q.choices}`+(q.diagram?"\n\n[도형·도식은 Word 또는 PDF 파일을 확인하세요.]":"")+(answers?`\n\n정답: ${q.answer}\n\n해설: ${q.explanation}`:"");})].join("\n\n");}
