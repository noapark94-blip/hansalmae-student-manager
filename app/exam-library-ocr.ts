type Word={text:string;confidence:number};
type OCRResult={data:{text:string;confidence:number;words?:Word[]}};
type OCRWorker={recognize:(image:string)=>Promise<OCRResult>;terminate:()=>Promise<unknown>};
type TesseractAPI={createWorker:(language:string,oem:number,options:{logger:(event:{status:string;progress:number})=>void})=>Promise<OCRWorker>};
declare global {interface Window {Tesseract?:TesseractAPI}}
let loader:Promise<TesseractAPI>|null=null;
function loadOCR(){
  if(window.Tesseract)return Promise.resolve(window.Tesseract);
  if(loader)return loader;
  loader=new Promise<TesseractAPI>((resolve,reject)=>{const script=document.createElement("script");script.src="https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js";script.crossOrigin="anonymous";const timeout=window.setTimeout(()=>{script.remove();loader=null;reject(new Error("사진 인식 도구를 불러오지 못했습니다. 인터넷 연결을 확인해 주세요."));},30000);script.onload=()=>{clearTimeout(timeout);if(window.Tesseract)resolve(window.Tesseract);else{loader=null;reject(new Error("사진 인식 도구를 초기화하지 못했습니다."));}};script.onerror=()=>{clearTimeout(timeout);loader=null;reject(new Error("사진 인식 도구를 불러오지 못했습니다. 텍스트 붙여넣기로 등록할 수 있습니다."));};document.head.appendChild(script);});return loader;
}
export async function readExamPhotos(sources:string[],language:string,columns:boolean,onProgress:(text:string)=>void,cancelled:()=>boolean){
  const api=await loadOCR();if(cancelled())throw new Error("사진 인식을 취소했습니다.");
  const worker=await api.createWorker(language,1,{logger:e=>onProgress(e.status==="recognizing text"?`글자 읽는 중 · ${Math.round(e.progress*100)}%`:"사진 인식 도구 준비 중…")});
  try{const texts:string[]=[];const uncertain:string[]=[];for(let i=0;i<sources.length;i++){if(cancelled())throw new Error("사진 인식을 취소했습니다.");const image=await loadPhoto(sources[i]);const regions=columns?[{x:0,y:0,w:50,h:100},{x:50,y:0,w:50,h:100}]:[{x:0,y:0,w:100,h:100}];for(const region of regions){if(cancelled())throw new Error("사진 인식을 취소했습니다.");onProgress(`${i+1}/${sources.length}장 인식 중…`);const result=await worker.recognize(cropPhoto(image,region,2500));texts.push(result.data.text);uncertain.push(...(result.data.words??[]).filter(w=>w.confidence<70&&w.text.trim()).map(w=>w.text));}}return {text:texts.join("\n\n"),uncertain:Array.from(new Set(uncertain)).slice(0,60)};}finally{await worker.terminate();}
}
export function loadPhoto(src:string):Promise<HTMLImageElement>{return new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=()=>reject(new Error("사진을 열 수 없습니다. JPG 또는 PNG로 다시 올려 주세요."));image.src=src;});}
export function cropPhoto(image:HTMLImageElement,region:{x:number;y:number;w:number;h:number},maxWidth=1200){
  const x=image.naturalWidth*region.x/100,y=image.naturalHeight*region.y/100,w=Math.min(image.naturalWidth-x,image.naturalWidth*region.w/100),h=Math.min(image.naturalHeight-y,image.naturalHeight*region.h/100);const scale=Math.min(1,maxWidth/w);const canvas=document.createElement("canvas");canvas.width=Math.max(1,Math.round(w*scale));canvas.height=Math.max(1,Math.round(h*scale));const ctx=canvas.getContext("2d");if(!ctx)throw new Error("이미지를 준비하지 못했습니다.");ctx.fillStyle="#fff";ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,x,y,w,h,0,0,canvas.width,canvas.height);return canvas.toDataURL("image/jpeg",.88);
}
