import type {UserRole} from './supabase';
export function notificationSources(role:UserRole){return {staff:['admin','sub_admin','teacher','manager'].includes(role),family:role==='guardian',general:role==='guardian'||role==='student'||role==='assistant'};}
export function singleFlight<T>(read:()=>Promise<T>){let pending:Promise<T>|null=null;return ()=>{if(pending)return pending;pending=(async()=>{try{return await read();}finally{pending=null;}})();return pending;};}
