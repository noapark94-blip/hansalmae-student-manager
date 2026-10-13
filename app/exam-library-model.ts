export type ExamQuestion = { id:string; number:string; passage:string; prompt:string; choices:string; answer:string; explanation:string; diagram:string };
export type ExamDraft = { title:string; subject:string; school:string; grade:string; year:number; term:string; exam_kind:string; description:string; questions:ExamQuestion[] };
export type ExamRecord = ExamDraft & { id:string; owner_id:string; version:number; updated_at:string };
export type ExamSummary = Omit<ExamRecord,"questions"> & { question_count:number; content_bytes:number };
export const newQuestion = (number=1):ExamQuestion => ({id:crypto.randomUUID(),number:String(number),passage:"",prompt:"",choices:"",answer:"",explanation:"",diagram:""});
export const newExam = ():ExamDraft => ({title:"",subject:"영어",school:"",grade:"고2",year:new Date().getFullYear(),term:"1학기",exam_kind:"중간고사",description:"",questions:[newQuestion()]});
export function splitExamText(text:string):ExamQuestion[]{
  const lines=text.replace(/\r\n?/g,"\n").split("\n");
  const groups:{number:string;text:string[]}[]=[];
  for(const line of lines){const match=line.match(/^\s*(\d{1,3})[.)．]\s+(.+)$/);if(match&&Number(match[1])<=200){groups.push({number:match[1],text:[match[2]]});}else if(groups.length)groups[groups.length-1].text.push(line);else if(line.trim())groups.push({number:"1",text:[line]});}
  return groups.length?groups.map((g,i)=>{const q=newQuestion(i+1);q.number=g.number;const all=g.text.join("\n").trim();const at=all.search(/(?:^|\n)\s*[①②③④⑤]/);q.passage=at<0?all:all.slice(0,at).trim();q.choices=at<0?"":all.slice(at).trim();return q;}):[newQuestion()];
}
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
export function questionHtml(q:ExamQuestion,index:number,answers:boolean){const format=(s:string)=>formattedParts(s).map(p=>p.bold?`<strong>${escapeHtml(p.text)}</strong>`:p.underline?`<u>${escapeHtml(p.text)}</u>`:escapeHtml(p.text)).join("");return `<article><h2>${index+1}. ${format(q.prompt)}</h2>${q.passage?`<div class="passage">${format(q.passage)}</div>`:""}${q.diagram&&safeDiagram(q.diagram)?`<img class="diagram" src="${q.diagram}" alt="문제 도형">`:""}${q.choices?`<div class="choices">${format(q.choices)}</div>`:""}${answers?`<div class="answer"><b>정답</b> ${format(q.answer)}${q.explanation?`\n<b>해설</b> ${format(q.explanation)}`:""}</div>`:""}</article>`;}
