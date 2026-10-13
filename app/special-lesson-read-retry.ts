type ReadError={message?:string;code?:string;status?:number};
function readError(value:unknown):ReadError{return value&&typeof value==="object"?value as ReadError:{message:String(value??"")};}
export function isTransientSpecialRead(error:unknown,status?:number){
 if(!error)return false;const detail=readError(error);
 return [408,429,502,503,504].includes(status??detail.status??0)||/upstream connect error|disconnect\/reset|protocol error|failed to fetch|fetch failed|networkerror|network error|load failed|bad gateway|service unavailable|gateway timeout|connection reset/i.test(detail.message??"");
}
export function specialReadMessage(error:unknown,context="수업 정보"){
 const detail=readError(error);
 if(isTransientSpecialRead(error))return context+"를 불러오는 중 연결이 끊겼습니다. 잠시 후 다시 불러와 주세요.";
 if(detail.code==="42501"||/permission denied|권한/.test(detail.message??""))return context+"를 조회할 권한을 확인해 주세요.";
 if(detail.code==="PGRST301"||/jwt expired|invalid jwt/i.test(detail.message??""))return "로그인 연결이 만료됐습니다. 다시 로그인해 주세요.";
 return context+"를 불러오지 못했습니다. 다시 불러오기를 눌러 주세요.";
}
export async function retrySpecialRead<T extends {error:unknown;status?:number}>(factory:()=>PromiseLike<T>,isCurrent:()=>boolean=()=>true,wait:(ms:number)=>Promise<void>=ms=>new Promise(resolve=>setTimeout(resolve,ms))):Promise<T>{
 for(let attempt=0;attempt<3;attempt++){
  if(!isCurrent())throw new Error("조회가 취소되었습니다.");
  try{const result=await factory();if(!isTransientSpecialRead(result.error,result.status)||attempt===2)return result;}
  catch(error){if(!isTransientSpecialRead(error)||attempt===2)throw error;}
  await wait(attempt===0?350:900);
 }
 throw new Error("조회하지 못했습니다.");
}
