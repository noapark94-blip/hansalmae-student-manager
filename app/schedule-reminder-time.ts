export const koreanDay=(now=new Date())=>new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(now);
export function untilNextKoreanDay(now=new Date()) {
  const start=Date.parse(`${koreanDay(now)}T00:00:00+09:00`);
  return Math.max(1000,start+86400000-now.getTime()+250);
}
