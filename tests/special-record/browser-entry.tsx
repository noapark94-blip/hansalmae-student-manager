import React from 'react';
import {createRoot} from 'react-dom/client';
import {SpecialLessonLearningBoard} from '../../app/special-lesson-learning-board';
import {NotificationCenter} from '../../app/notification-center';
import {EditConflictDialogHost} from '../../app/edit-conflict-dialog';
import {AppDialogHost} from '../../app/app-dialog';
const w=window as any;
w.calls=[];w.changes=[];
const values={notice:'',lessonContent:'',students:{a:{status:'present',lateMinutes:null,absenceReason:'',note:'',lessonContent:'',assignedHomework:'',inspectionStatus:'',inspectionNote:'',exam_id:'',exam_examType:'',exam_examTitle:'',exam_score:'',exam_maxScore:'100',exam_evaluation:'',exam_feedback:''}}};
function snapshot(){const v=values.students.a;return {values:structuredClone(values),state:'draft',board:{notice:values.notice,state:'draft',students:[{id:'a',name:'테스트 학생',school:'테스트학교',grade:'고1',status:v.status,lateMinutes:v.lateMinutes,absenceReason:v.absenceReason,lessonContent:v.lessonContent,assignedHomework:v.assignedHomework,inspectionStatus:v.inspectionStatus,inspectionNote:v.inspectionNote,previousHomework:'',exam:{examType:v.exam_examType,examTitle:v.exam_examTitle,score:null,maxScore:100,evaluation:''}}]}};}
const supabase:any={rpc:async(name:string,args:any)=>{w.calls.push({name,args});if(name==='staff_special_edit_snapshot')return {data:snapshot(),error:null};if(name==='staff_exam_categories')return {data:[],error:null};if(name==='staff_patch_special_record'){await new Promise(r=>setTimeout(r,w.saveDelay??0));for(const c of args.p_changes){const current=c.path.length===1?(values as any)[c.path[0]]:(values.students as any)[c.path[1]][c.path[2]];if(current!==c.before&&current!==c.value)return {data:null,error:{message:'다른 선생님이 먼저 같은 항목을 수정했습니다.'}};}for(const c of args.p_changes){if(c.path.length===1)(values as any)[c.path[0]]=c.value;else (values.students as any)[c.path[1]][c.path[2]]=c.value;}return {data:snapshot(),error:null};}return {data:{unreadCount:0,items:[],students:[]},error:null};}};
const root=createRoot(document.getElementById('root')!);
w.remote=(text:string)=>values.students.a.lessonContent=text;
w.renderSpecial=()=>root.render(<><SpecialLessonLearningBoard embedded supabase={supabase} profile={{id:'teacher',role:'teacher',display_name:'선생님'}} sessionId="test" lessonKind="makeup" onClose={()=>{}} onAttendanceChange={change=>{w.changes.push(change)}}/><AppDialogHost/></>);
w.renderNotifications=(role:any)=>root.render(<><div style={{display:'none'}}><NotificationCenter key={'hidden'+role} supabase={supabase} role={role}/></div><NotificationCenter key={role} supabase={supabase} role={role}/></>);
w.renderSpecial();
