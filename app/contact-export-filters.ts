import type { ContactStudent } from "./contact-export-model";
export type ContactFilters = {schools:string[];grades:string[];subjects:string[];classes:string[];statuses:string[];query:string};
export const defaultContactFilters=():ContactFilters=>({schools:[],grades:[],subjects:[],classes:[],statuses:["active"],query:""});
export const contactStatus=(status:string)=>({재원:"active",휴원:"paused",퇴원:"completed"}[status]??status);
export function matchesContactFilters(row:ContactStudent,f:ContactFilters){
 const enrollments=(row.enrollments??[]).filter(e=>e.status==="active"&&e.classes);
 return (!f.schools.length||f.schools.includes(row.school?.trim()||"학교 미등록"))&&(!f.grades.length||f.grades.includes(row.grade?.trim()||"학년 미등록"))&&(!f.statuses.length||f.statuses.includes(contactStatus(row.status)))&&
 ((!f.subjects.length&&!f.classes.length)||enrollments.some(e=>(!f.subjects.length||f.subjects.includes(e.classes!.subject))&&(!f.classes.length||f.classes.includes(e.class_id))))&&
 (!f.query.trim()||[row.name,row.school,row.grade,...enrollments.map(e=>e.classes!.name)].join(" ").toLocaleLowerCase().includes(f.query.trim().toLocaleLowerCase()));
}
