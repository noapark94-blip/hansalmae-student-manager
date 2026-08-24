"use client";

import type { FormEvent, ReactNode } from "react";
import { useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient, User } from "@supabase/supabase-js";
import { createSupabaseBrowserClient, type AcademyClass, type Profile, type StudentRow, type UserRole } from "./supabase";
import { TeacherScheduleHub } from "./teacher-schedule-hub";
import { AttendanceBoard } from "./attendance-board";
import { MakeupBoard } from "./makeup-board";
import { AssignmentBoard } from "./assignment-board";
import { ConsultationBoard } from "./consultation-board";
import { CommunicationBoard } from "./communication-board";
import { SettingsBoard } from "./settings-board";
import { AccountDeletionPanel } from "./account-deletion-panel";
import { MyAccount } from "./my-account";
import { StudentDetailHub } from "./student-detail-hub";
import { FamilyLiveDashboard } from "./family-dashboard";
import { StudentLifecycleDashboard, type StudentStatusFilter } from "./student-lifecycle-dashboard";
import { NotificationCenter } from "./notification-center";
import { TuitionBoard } from "./tuition-board";
import { OperationsAnalytics } from "./operations-analytics";
import { BackupBoard } from "./backup-board";
import { BulkImportBoard } from "./bulk-import-board";
import { BulkAccountBoard } from "./bulk-account-board";
import { SidebarNavigation } from "./sidebar-navigation";
import { reorderById, useSortableOrder } from "./use-sortable-order";
import { BulkRegistrationGuide } from "./bulk-registration-guide";
import { TeacherClassWorkspace } from "./teacher-class-workspace";
import type { WeeklyTimetableRow } from "./weekly-timetable";
import { HansalmaeIcon, viewIcon } from "./hansalmae-icons";

export type View = "dashboard" | "students" | "bulk-import" | "bulk-accounts" | "guide" | "class-management" | "schedule" | "corrections" | "transport" | "attendance" | "makeups" | "assignments" | "consultations" | "communications" | "tuition" | "analytics" | "backup" | "settings" | "my-account" | "audit";

const VIEW_STORAGE_KEY = "hansalmae:last-view";
const VIEW_VALUES: readonly View[] = ["dashboard", "students", "bulk-import", "bulk-accounts", "guide", "class-management", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "communications", "tuition", "analytics", "backup", "settings", "my-account", "audit"];
const isView = (value: string): value is View => VIEW_VALUES.includes(value as View);
type StudentFormValues = { name: string; school: string; grade: string; phone: string; guardianName: string; guardianPhone: string; residence:string; pickupLocation:string; dropoffLocation:string; status: string; internalNote: string; classIds:string[] };
type StudentDetails = { id: string; name: string; school: string; grade: string; phone: string; residence:string; pickupLocation:string; dropoffLocation:string; status: string; internalNote: string; guardianName?:string; guardianPhone?:string };
type ClassFormValues = { name: string; subject: string; subjectId:string; room: string; color: string };
type SubjectOption={id:string;name:string;main_subject:string;parent_id:string|null};
type SchoolOption={id:string;name:string};
type LiveTodayClass = { id: string; time: string; name: string; room: string | null; color: string; teachers: string; enrolled: number; present: number };
type LiveAttendance = { present: number; late: number; absent: number; checked: number };
type LiveDashboard = { todayClasses: LiveTodayClass[]; attendance: LiveAttendance & { makeup: number }; weekAttendance: (LiveAttendance & { weekday: number })[] };
type AssignmentCount = { unsubmitted: number; reviewPending: number; total: number };
type ConsultationCount = { overdue: number; upcoming: number };
type PauseReturnAlerts={overdue:number;upcoming:number;students:{id:string;name:string;expectedOn:string;overdue:boolean}[]};

function formatPhoneNumber(value:string){
  const digits=value.replace(/\D/g,"").slice(0,11);
  if(digits.length<=3)return digits;
  if(digits.length<=7)return `${digits.slice(0,3)}-${digits.slice(3)}`;
  return `${digits.slice(0,3)}-${digits.slice(3,7)}-${digits.slice(7)}`;
}

const nav: { id: View; label: string; icon: string }[] = [
  { id: "dashboard", label: "홈", icon: "⌂" },
  { id: "students", label: "학생", icon: "人" },
  { id: "bulk-import", label: "학생 일괄 등록", icon: "＋" },
  { id: "bulk-accounts", label: "계정 일괄 생성", icon: "♙" },
  { id: "guide", label: "일괄 등록 설명서", icon: "?" },
  { id: "class-management", label: "클래스 관리", icon: "▤" },
  { id: "schedule", label: "전과목 시간표", icon: "▦" },
  { id: "corrections", label: "첨삭 시간표", icon: "✎" },
  { id: "transport", label: "차량 운행표", icon: "◇" },
  { id: "attendance", label: "출결 입력", icon: "✓" },
  { id: "makeups", label: "보강 일정", icon: "↻" },
  { id: "assignments", label: "과제·첨삭", icon: "✎" },
  { id: "consultations", label: "상담", icon: "☏" },
  { id: "communications", label: "공지·문자", icon: "▣" },
  { id: "tuition", label: "원비 정산", icon: "₩" },
  { id: "analytics", label: "운영 현황", icon: "▥" },
  { id: "backup", label: "데이터 백업", icon: "⇩" },
  { id: "settings", label: "계정·역할", icon: "⚙" },
  { id: "my-account", label: "내 계정", icon: "♙" },
];

const roleLabels: Record<UserRole, string> = {
  admin: "관리자",
  teacher: "교사",
  student: "학생",
  guardian: "학부모",
};

const roleViews: Record<UserRole, View[]> = {
  admin: ["dashboard", "students", "bulk-import", "bulk-accounts", "guide", "class-management", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "communications", "tuition", "analytics", "backup", "settings", "my-account", "audit"],
  teacher: ["dashboard", "students", "guide", "class-management", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "my-account"],
  student: ["dashboard", "schedule", "attendance", "makeups", "assignments", "communications", "my-account"],
  guardian: ["dashboard", "schedule", "attendance", "makeups", "consultations", "communications", "my-account"],
};

const notices = [
  { label: "상담", text: "마지막 상담 후 30일이 지난 학생", count: 7, tone: "wine" },
  { label: "과제", text: "오늘까지 제출하지 않은 과제", count: 12, tone: "amber" },
  { label: "보강", text: "이번 주 예정된 보강 수업", count: 5, tone: "blue" },
];

export default function Home() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const [authReady, setAuthReady] = useState(!supabase);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authError, setAuthError] = useState("");
  const profileLoadSequence = useRef(0);
  const [view, setView] = useState<View>("dashboard");
  const [viewRestored, setViewRestored] = useState(false);
  const [query, setQuery] = useState("");
  const [searchOpen,setSearchOpen]=useState(false);
  const [adminHomeMode,setAdminHomeMode]=useState<"operations"|"classes">("operations");
  const [mobileNav, setMobileNav] = useState(false);
  const [staffMoreOpen, setStaffMoreOpen] = useState(false);
  const [toast, setToast] = useState("");
  const [students, setStudents] = useState<StudentRow[]>([]);
  const [studentTimetables,setStudentTimetables]=useState<Record<string,WeeklyTimetableRow[]>>({});
  const [studentsLoading, setStudentsLoading] = useState(false);
  const [studentsError, setStudentsError] = useState("");
  const [registrationOpen, setRegistrationOpen] = useState(false);
  const [academyClasses, setAcademyClasses] = useState<AcademyClass[]>([]);
  const [academySubjects,setAcademySubjects]=useState<SubjectOption[]>([]);
  const [academySchools,setAcademySchools]=useState<SchoolOption[]>([]);
  const [classRegistrationOpen, setClassRegistrationOpen] = useState(false);
  const [enrollmentStudent, setEnrollmentStudent] = useState<StudentRow | null>(null);
  const [studentDetails, setStudentDetails] = useState<StudentDetails | null>(null);
  const [studentStatusFilter, setStudentStatusFilter] = useState<StudentStatusFilter>("all");

  useEffect(() => {
    const savedView = window.localStorage.getItem(VIEW_STORAGE_KEY);
    if (savedView && isView(savedView)) setView(savedView);
    setViewRestored(true);
  }, []);

  useEffect(() => {
    if (viewRestored) window.localStorage.setItem(VIEW_STORAGE_KEY, view);
  }, [view, viewRestored]);

  useEffect(() => {
    if (profile && !roleViews[profile.role].includes(view)) setView("dashboard");
  }, [profile, view]);

  useEffect(() => {
    if (!supabase) {
      return;
    }

    const loadProfile = async (nextUser: User | null) => {
      const loadSequence = ++profileLoadSequence.current;
      setAuthReady(false);
      setUser(nextUser);
      if (!nextUser) {
        setProfile(null);
        setAuthError("");
        setAuthReady(true);
        return;
      }

      let role: string | null = null;
      let roleError = false;
      let ownProfile: { display_name: string } | null = null;
      const retryDelays = [0, 250, 650];

      for (const retryDelay of retryDelays) {
        if (retryDelay) await new Promise((resolve) => window.setTimeout(resolve, retryDelay));
        if (loadSequence !== profileLoadSequence.current) return;
        const [roleResult, profileResult] = await Promise.all([
          supabase.rpc("current_user_role"),
          supabase.from("profiles").select("display_name").eq("id", nextUser.id).maybeSingle(),
        ]);
        role = typeof roleResult.data === "string" ? roleResult.data : null;
        roleError = Boolean(roleResult.error);
        if (profileResult.data) ownProfile = profileResult.data;
        if (!roleError && role && roleViews[role as UserRole]) break;
      }

      if (loadSequence !== profileLoadSequence.current) return;

      if (roleError || !role || !roleViews[role as UserRole]) {
        setAuthError("계정 역할을 확인할 수 없습니다. 관리자에게 문의해 주세요.");
        setProfile(null);
      } else {
        if (role === "student" || role === "guardian" || ((role === "admin" || role === "teacher") && window.matchMedia("(max-width: 760px)").matches)) setView("dashboard");
        setAuthError("");
        setProfile({
          id: nextUser.id,
          role: role as UserRole,
          display_name:
            ownProfile?.display_name ??
            nextUser.user_metadata.display_name ??
            nextUser.user_metadata.full_name ??
            nextUser.email?.split("@")[0] ??
            "사용자",
        });
      }
      setAuthReady(true);
    };

    void supabase.auth.getUser().then(({ data }) => loadProfile(data.user));
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      window.setTimeout(() => void loadProfile(session?.user ?? null), 0);
    });
    return () => listener.subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!supabase || !profile || (profile.role !== "admin" && profile.role !== "teacher")) {
      return;
    }

    let active = true;
    const loadStudents = async () => {
      setStudentsLoading(true);
      setStudentsError("");
      const [{ data, error }, { data: classData, error: classError },{data:subjectData,error:subjectError},{data:timetableData,error:timetableError},{data:attendanceData,error:attendanceError}] = await Promise.all([
        supabase.rpc("staff_student_roster"),
        supabase.from("classes").select("id, name, subject, subject_id, room, color, active").eq("active", true).order("name"),
        supabase.from("academy_subjects").select("id,name,main_subject,parent_id").eq("active",true).order("main_subject").order("name"),
        supabase.rpc("staff_student_weekly_timetables"),
        supabase.rpc("staff_student_attendance_rates",{p_days:30}),
      ]);

      if (!active) return;
      if (error || classError || subjectError || timetableError || attendanceError) {
        setStudentsError("학생 데이터를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.");
        setStudents([]);
      } else {
        const attendanceByStudent=new Map(((attendanceData??[]) as {student_id:string;checked_count:number;attendance_rate:number|null}[]).map((row)=>[row.student_id,row]));
        setStudents(((data ?? []) as StudentRow[]).map((student)=>{const attendance=attendanceByStudent.get(student.id);return{...student,attendanceRate:attendance?.attendance_rate??null,attendanceChecked:Number(attendance?.checked_count??0)};}).sort((a, b) => a.name.localeCompare(b.name, "ko")));
        setAcademyClasses((classData ?? []) as AcademyClass[]);
        setAcademySubjects((subjectData??[]) as SubjectOption[]);
        const grouped:Record<string,WeeklyTimetableRow[]>={};
        for(const entry of (timetableData??[]) as {studentId:string;rows:WeeklyTimetableRow[]}[])grouped[entry.studentId]=entry.rows??[];
        setStudentTimetables(grouped);
      }
      setStudentsLoading(false);
    };

    void loadStudents();
    return () => { active = false; };
  }, [profile, supabase]);

  const allowedNav = useMemo(() => profile ? nav.filter((item) => roleViews[profile.role].includes(item.id)) : [], [profile]);

  const filteredStudents = useMemo(() => {
    const q = query.trim().toLowerCase();
    return students.filter((student) => {
      const matchesStatus=studentStatusFilter==="all"||normalizeStudentStatus(student.status)===studentStatusFilter;
      const matchesQuery=!q||[student.name, student.school ?? "", student.grade ?? "", ...getStudentSubjects(student)].some((value) => value.toLowerCase().includes(q));
      return matchesStatus&&matchesQuery;
    });
  }, [query, studentStatusFilter, students]);

  const globalSearch=useMemo(()=>{
    const text=query.trim().toLowerCase();
    if(!text)return{students:[] as StudentRow[],classes:[] as AcademyClass[]};
    return{
      students:students.filter((student)=>[student.name,student.school??"",student.grade??"",...getStudentSubjects(student)].some((value)=>value.toLowerCase().includes(text))).slice(0,6),
      classes:academyClasses.filter((item)=>[item.name,item.subject,item.room??""].some((value)=>value.toLowerCase().includes(text))).slice(0,6),
    };
  },[academyClasses,query,students]);

  const selectView = (next: View) => {
    if (profile && !roleViews[profile.role].includes(next)) {
      showToast("이 역할에서는 접근할 수 없는 메뉴예요.");
      return;
    }
    setView(next);
    setMobileNav(false);
    setStaffMoreOpen(false);
    setQuery("");
    setSearchOpen(false);
  };

  if (!authReady) return <LoadingScreen />;
  if (!supabase) return <ConfigurationScreen />;
  if (!user) return <LoginScreen supabase={supabase} onSubmit={async (email, password) => {
    setAuthError("");
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setAuthError("이메일 또는 비밀번호를 확인해 주세요.");
  }} error={authError} />;
  if (!profile) return <AccessPendingScreen email={user.email ?? ""} error={authError} onSignOut={() => void supabase.auth.signOut()} />;

  const showToast = (message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2200);
  };

  const refreshStudentRegistrationCatalog = async () => {
    const [{ data:classData, error:classError },{data:schoolData,error:schoolError}] = await Promise.all([
      supabase.rpc("staff_student_registration_classes"),
      supabase.rpc("staff_registration_schools"),
    ]);
    if (classError || schoolError) {
      showToast(`학생 등록 항목을 불러오지 못했습니다. ${(classError??schoolError)?.message??"다시 시도해 주세요."}`);
      return false;
    }
    setAcademyClasses((classData ?? []) as AcademyClass[]);
    setAcademySchools((schoolData??[]) as SchoolOption[]);
    return true;
  };

  const addRegistrationSchool=async(name:string)=>{
    const{data,error}=await supabase.rpc("staff_create_school",{p_name:name});
    if(error)throw error;
    const{data:schoolData,error:schoolError}=await supabase.rpc("staff_registration_schools");
    if(schoolError)throw schoolError;
    const nextSchools=(schoolData??[]) as SchoolOption[];
    setAcademySchools(nextSchools);
    return nextSchools.find((item)=>item.id===String(data))?.name??name.trim();
  };

  const deleteRegistrationSchool=async(id:string)=>{
    const{error}=await supabase.rpc("staff_delete_school",{p_school_id:id});
    if(error)throw error;
    setAcademySchools((current)=>current.filter((item)=>item.id!==id));
  };

  const reorderRegistrationSchools=async(next:SchoolOption[])=>{
    setAcademySchools(next);
    const{error}=await supabase.rpc("save_user_school_order",{p_ids:next.map((item)=>item.id)});
    if(error)throw error;
  };

  const registerStudent = async (values: StudentFormValues) => {
    const { data, error } = await supabase.rpc("staff_register_student_with_guardian", {
      p_name: values.name.trim(),
      p_school: values.school.trim() || null,
      p_grade: values.grade.trim() || null,
      p_phone: values.phone.trim() || null,
      p_status: values.status,
      p_internal_note: values.internalNote.trim() || null,
      p_guardian_name: values.guardianName.trim() || null,
      p_guardian_phone: values.guardianPhone.trim() || null,
    });

    if (error || !data) throw error ?? new Error("student registration returned no data");
    const created = { ...(data as unknown as Omit<StudentRow, "enrollments">), enrollments: [] } as StudentRow;
    const{error:vehicleInfoError}=await supabase.from("students").update({residence:values.residence.trim()||null,vehicle_pickup_location:values.pickupLocation.trim()||null,vehicle_dropoff_location:values.dropoffLocation.trim()||null}).eq("id",created.id);
    if(vehicleInfoError)throw vehicleInfoError;
    if(values.classIds.length){
      const{error:enrollmentError}=await supabase.rpc("staff_sync_student_enrollments",{p_student_id:created.id,p_class_ids:values.classIds});
      if(enrollmentError)throw enrollmentError;
      created.enrollments=values.classIds.map((classId)=>{const selected=academyClasses.find((item)=>item.id===classId);return{class_id:classId,status:"active",classes:selected?{name:selected.name,subject:selected.subject}:null};});
    }
    setStudents((current) => [...current, created].sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setStudentsError("");
    setRegistrationOpen(false);
    setView("students");
    showToast(`${created.name} 학생을 등록했습니다.`);
  };

  const registerClass = async (values: ClassFormValues) => {
    const { data, error } = await supabase.from("classes").insert({ name: values.name.trim(), subject: values.subject.trim(),subject_id:values.subjectId||null, room: values.room.trim() || null, color: values.color }).select("id, name, subject, subject_id, room, color, active").single();
    if (error) throw error;
    setAcademyClasses((current) => [...current, data as AcademyClass].sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setClassRegistrationOpen(false);
    showToast(`${data.name} 클래스를 등록했습니다.`);
  };

  const saveClassAssignments = async (student: StudentRow, classIds: string[]) => {
    const{error}=await supabase.rpc("staff_sync_student_enrollments",{p_student_id:student.id,p_class_ids:classIds});
    if(error)throw error;
    const nextEnrollments=classIds.map((classId)=>{const selected=academyClasses.find((item)=>item.id===classId);return{class_id:classId,status:"active" as const,classes:selected?{name:selected.name,subject:selected.subject}:null};});
    setStudents((current) => current.map((item) => item.id === student.id ? { ...item, enrollments:nextEnrollments } : item));
    showToast(`${student.name} 학생의 수강 클래스 ${classIds.length}개를 저장했습니다.`);
  };

  const openStudentDetails = async (student: StudentRow) => {
    const { data, error } = await supabase.from("students").select("id, name, school, grade, phone, residence, vehicle_pickup_location, vehicle_dropoff_location, status, internal_note").eq("id", student.id).single();
    if (error) { showToast("학생 상세 정보를 불러오지 못했습니다."); return; }
    setStudentDetails({ id: data.id, name: data.name, school: data.school ?? "", grade: data.grade ?? "", phone: data.phone ?? "", residence:data.residence??"", pickupLocation:data.vehicle_pickup_location??"", dropoffLocation:data.vehicle_dropoff_location??"", status: data.status, internalNote: data.internal_note ?? "" });
  };

  const updateStudent = async (values: StudentDetails) => {
    const { data, error } = await supabase.rpc("staff_update_student_profile_with_guardian",{p_student_id:values.id,p_name:values.name.trim(),p_school:values.school.trim()||null,p_grade:values.grade.trim()||null,p_phone:values.phone.trim()||null,p_residence:values.residence.trim()||null,p_pickup_location:values.pickupLocation.trim()||null,p_dropoff_location:values.dropoffLocation.trim()||null,p_status:values.status,p_internal_note:values.internalNote.trim()||null,p_guardian_name:values.guardianName?.trim()||null,p_guardian_phone:values.guardianPhone?.trim()||null});
    if (error) throw error;
    const saved=data as {id:string;name:string;school:string|null;grade:string|null;status:string};
    setStudents((current) => current.map((student) => student.id === values.id ? { ...student, ...saved } : student).sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setStudentDetails(null);
    showToast(`${saved.name} 학생 정보를 수정했습니다.`);
  };

  const deleteStudent = async (student: StudentDetails) => {
    const { error } = await supabase.from("students").delete().eq("id", student.id);
    if (error) throw error;
    setStudents((current) => current.filter((item) => item.id !== student.id));
    setStudentDetails(null);
    showToast(`${student.name} 학생을 삭제했습니다.`);
  };

  const familyAccount=profile.role==="student"||profile.role==="guardian";
  const staffAccount=profile.role==="admin"||profile.role==="teacher";

  return (
    <main className={`app-shell${familyAccount?" family-app-shell":""}${staffAccount?" staff-app-shell":""}`}>
      {!familyAccount&&<aside className={`sidebar ${mobileNav ? "is-open" : ""}`}>
        <button className="brand" type="button" onClick={() => selectView("dashboard")} aria-label="홈으로 이동">
          <img className="brand-mark" src="/hansalmae-logo.png" alt="한살매 로고" />
          <div><strong>한살매</strong><span>수업노트</span></div>
        </button>
        <SidebarNavigation supabase={supabase} role={profile.role} items={allowedNav} activeView={view} onSelect={selectView} />
        <div className="sidebar-bottom">
          <div className="teacher-card"><div className="avatar">{profile.display_name.slice(0, 1)}</div><div><b>{profile.display_name}</b><span>{roleLabels[profile.role]}</span></div><button className="signout-button" onClick={() => void supabase.auth.signOut()}>로그아웃</button></div>
        </div>
      </aside>}

      {!familyAccount&&mobileNav && <button className="backdrop" aria-label="메뉴 닫기" onClick={() => setMobileNav(false)} />}

      <section className={`workspace${familyAccount?" family-app-workspace":""}`}>
        {familyAccount?<header className="family-app-topbar"><button type="button" className="family-app-brand" onClick={()=>selectView("dashboard")} aria-label="한살매 홈으로 이동"><img src="/hansalmae-logo.png" alt=""/><span><b>한살매</b><small>수업노트</small></span></button><div><NotificationCenter supabase={supabase}/><button type="button" className="family-account-button" onClick={()=>selectView("my-account")} aria-label="내 정보"><HansalmaeIcon name="user" size={21}/></button></div></header>:<><header className="staff-app-topbar"><button type="button" className="staff-app-brand" onClick={()=>selectView("dashboard")} aria-label="한살매 수업노트 홈으로 이동"><img src="/hansalmae-logo.png" alt=""/><b>한살매 수업노트</b><small>{profile.role==="admin"?"관리자":"선생님"}</small></button><div><NotificationCenter supabase={supabase}/><button type="button" className="staff-account-button" onClick={()=>selectView("my-account")} aria-label="내 계정"><span>{profile.display_name.slice(0,1)}</span></button></div></header><header className="topbar">
          <button className="menu-button" aria-label="메뉴 열기" onClick={() => setMobileNav(true)}>☰</button>
          <div className="global-search"><div className="search-wrap"><span>⌕</span><input value={query} onFocus={()=>setSearchOpen(true)} onChange={(event) => {setQuery(event.target.value);setSearchOpen(true);}} onKeyDown={(event)=>{if(event.key==="Escape")setSearchOpen(false);if(event.key==="Enter"){const firstStudent=globalSearch.students[0];const firstClass=globalSearch.classes[0];if(firstStudent){void openStudentDetails(firstStudent);setSearchOpen(false);}else if(firstClass){selectView("schedule");showToast(`${firstClass.name} 클래스를 시간표에서 확인해 주세요.`);}}}} placeholder="학생, 클래스 검색" /></div>{searchOpen&&query.trim()&&<div className="global-search-results">{globalSearch.students.map((student)=><button key={student.id} onClick={()=>{void openStudentDetails(student);setSearchOpen(false);}}><i>{student.name.slice(0,1)}</i><span><b>{student.name}</b><small>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생"}</small></span><em>학생 보기</em></button>)}{globalSearch.classes.map((item)=><button key={item.id} onClick={()=>{selectView("schedule");showToast(`${item.name} 클래스를 시간표에서 확인해 주세요.`);}}><i style={{color:item.color}}>▦</i><span><b>{item.name}</b><small>{item.subject}{item.room?` · ${item.room}`:""}</small></span><em>시간표 보기</em></button>)}{!globalSearch.students.length&&!globalSearch.classes.length&&<p>검색 결과가 없습니다.</p>}</div>}</div>
          <NotificationCenter supabase={supabase} />
          {(profile.role === "admin" || profile.role === "teacher") && <button className="primary small" onClick={() => void refreshStudentRegistrationCatalog().then((ready)=>ready&&setRegistrationOpen(true))}>＋ 학생 등록</button>}
        </header></>}

        <div className={`content${familyAccount?" family-app-content":""}`}>
          {view === "dashboard" && staffAccount&&<StaffMobileHomeHero role={profile.role as "admin"|"teacher"} displayName={profile.display_name} activeStudentCount={students.filter(isActiveStudent).length} studentsLoading={studentsLoading} onNavigate={selectView} onRegister={()=>void refreshStudentRegistrationCatalog().then((ready)=>ready&&setRegistrationOpen(true))}/>} 
          {view === "dashboard" && profile.role==="admin"&&<><div className="admin-home-switch"><button className={adminHomeMode==="operations"?"active":""} onClick={()=>setAdminHomeMode("operations")}>학원 운영</button><button className={adminHomeMode==="classes"?"active":""} onClick={()=>setAdminHomeMode("classes")}>내 수업</button></div>{adminHomeMode==="operations"?<Dashboard supabase={supabase} profile={profile} activeStudentCount={students.filter(isActiveStudent).length} studentsLoading={studentsLoading} onNavigate={selectView}/>:<TeacherClassWorkspace supabase={supabase} profile={profile} onClassesChanged={()=>void refreshStudentRegistrationCatalog()}/>}</>}
          {view === "dashboard" && profile.role==="teacher"&&<TeacherClassWorkspace supabase={supabase} profile={profile} onClassesChanged={()=>void refreshStudentRegistrationCatalog()}/>} 
          {view === "dashboard" && (profile.role==="student"||profile.role==="guardian")&&<Dashboard supabase={supabase} profile={profile} activeStudentCount={students.filter(isActiveStudent).length} studentsLoading={studentsLoading} onNavigate={selectView}/>}
          {view === "students" && <div className="student-page-layout">{profile.role==="admin"&&<StudentLifecycleDashboard supabase={supabase} filter={studentStatusFilter} onFilter={setStudentStatusFilter}/>}<Students rows={filteredStudents} allRows={students} total={students.length} statusFilter={studentStatusFilter} loading={studentsLoading} error={studentsError} query={query} setQuery={setQuery} onRegister={() => void refreshStudentRegistrationCatalog().then((ready)=>ready&&setRegistrationOpen(true))} onOpen={openStudentDetails} /></div>}
          {view === "bulk-import" && <BulkImportBoard supabase={supabase} />}
          {view === "bulk-accounts" && <BulkAccountBoard supabase={supabase} />}
          {view === "guide" && <BulkRegistrationGuide onNavigate={selectView} />}
          {view === "class-management" && <TeacherClassWorkspace supabase={supabase} profile={profile} manageOnly onClassesChanged={()=>void refreshStudentRegistrationCatalog()} />}
          {view === "schedule" && (profile.role === "admin" || profile.role === "teacher" ? <TeacherScheduleHub supabase={supabase} profile={profile} initialTab="all" /> : <Schedule classes={academyClasses} onRegister={() => setClassRegistrationOpen(true)} />)}
          {view === "corrections" && <TeacherScheduleHub supabase={supabase} profile={profile} initialTab="correction" />}
          {view === "transport" && <TeacherScheduleHub supabase={supabase} profile={profile} initialTab="vehicle" />}
          {view === "attendance" && (profile.role === "admin" || profile.role === "teacher" ? <AttendanceBoard supabase={supabase} /> : <SimplePanel title="출결·보강" description="내 수업의 출결 기록을 확인합니다." items={["출결 기록은 담당 선생님이 입력합니다."]} />)}
          {view === "makeups" && <MakeupBoard supabase={supabase} />}
          {view === "assignments" && <AssignmentBoard supabase={supabase} />}
          {view === "consultations" && <ConsultationBoard supabase={supabase} />}
          {view === "communications" && <CommunicationBoard supabase={supabase} />}
          {view === "tuition" && <TuitionBoard supabase={supabase} />}
          {view === "analytics" && <OperationsAnalytics supabase={supabase} onNavigate={selectView} />}
          {view === "backup" && <BackupBoard supabase={supabase} />}
          {view === "settings" && <><SettingsBoard supabase={supabase} /><AccountDeletionPanel supabase={supabase} /></>}
          {view === "audit" && <OperationsAnalytics supabase={supabase} onNavigate={selectView} />}
          {view === "my-account" && <MyAccount supabase={supabase} profile={profile} email={user.email ?? ""} onProfileUpdated={(displayName) => setProfile((current) => current ? { ...current, display_name:displayName } : current)} />}
          {view === "my-account" && familyAccount && <section className="family-signout-card" aria-label="로그인 관리"><div><b>로그인 관리</b><span>현재 계정에서 안전하게 로그아웃합니다.</span></div><button type="button" onClick={()=>void supabase.auth.signOut()}><span aria-hidden="true">↪</span>로그아웃</button></section>}
        </div>
        {familyAccount&&<FamilyBottomNavigation role={profile.role==="guardian"?"guardian":"student"} activeView={view} onSelect={selectView}/>} 
        {staffAccount&&<StaffBottomNavigation role={profile.role as "admin"|"teacher"} activeView={view} onSelect={selectView} onMore={()=>setStaffMoreOpen(true)}/>} 
      </section>
      {staffAccount&&staffMoreOpen&&<StaffMoreSheet items={allowedNav} activeView={view} displayName={profile.display_name} role={profile.role as "admin"|"teacher"} onSelect={selectView} onClose={()=>setStaffMoreOpen(false)} onSignOut={()=>void supabase.auth.signOut()}/>} 
      {registrationOpen && <StudentRegistrationModal classes={academyClasses} schools={academySchools} onAddSchool={addRegistrationSchool} onDeleteSchool={deleteRegistrationSchool} onReorderSchools={reorderRegistrationSchools} onClose={() => setRegistrationOpen(false)} onSubmit={registerStudent} />}
      {classRegistrationOpen && <ClassRegistrationModal subjects={academySubjects} onClose={() => setClassRegistrationOpen(false)} onSubmit={registerClass} />}
      {enrollmentStudent && <EnrollmentModal supabase={supabase} student={enrollmentStudent} classes={academyClasses} onClose={() => setEnrollmentStudent(null)} onSubmit={(classIds) => saveClassAssignments(enrollmentStudent, classIds)} />}
      {studentDetails && <StudentDetailHub supabase={supabase} student={studentDetails} rosterStudent={students.find((item) => item.id === studentDetails.id)} timetable={studentTimetables[studentDetails.id]??[]} onClose={() => setStudentDetails(null)} onUpdate={updateStudent} onDelete={deleteStudent} onAssign={(student) => { setStudentDetails(null); setEnrollmentStudent(student as StudentRow); }} onLifecycleUpdated={(status) => { setStudentDetails((current) => current ? { ...current, status } : current); setStudents((current) => current.map((item) => item.id === studentDetails.id ? { ...item, status, enrollments:status === "active" ? item.enrollments : item.enrollments.map((enrollment) => enrollment.status === "active" ? { ...enrollment, status:status === "paused" ? "paused" : "completed" } : enrollment) } : item)); }} />}
      {toast && <div className="toast" role="status">{toast}</div>}
    </main>
  );
}

function FamilyBottomNavigation({role,activeView,onSelect}:{role:"student"|"guardian";activeView:View;onSelect:(view:View)=>void}){
  const items:{id:View;label:string}[]=role==="student"?[{id:"dashboard",label:"홈"},{id:"schedule",label:"시간표"},{id:"assignments",label:"학습"},{id:"communications",label:"공지"},{id:"my-account",label:"내 정보"}]:[{id:"dashboard",label:"홈"},{id:"schedule",label:"시간표"},{id:"attendance",label:"출결"},{id:"consultations",label:"상담"},{id:"my-account",label:"내 정보"}];
  return <nav className="family-bottom-nav" aria-label="학생·학부모 주요 메뉴">{items.map(item=><button type="button" key={item.id} className={activeView===item.id?"active":""} aria-current={activeView===item.id?"page":undefined} onClick={()=>onSelect(item.id)}><HansalmaeIcon name={viewIcon[item.id]} size={21}/><span>{item.label}</span></button>)}</nav>;
}

function StaffMobileHomeHero({role,displayName,activeStudentCount,studentsLoading,onNavigate,onRegister}:{role:"admin"|"teacher";displayName:string;activeStudentCount:number;studentsLoading:boolean;onNavigate:(view:View)=>void;onRegister:()=>void}){
  const actions=role==="admin"?[{id:"students" as View,label:"학생 관리",tone:"blue"},{id:"schedule" as View,label:"시간표",tone:"green"},{id:"attendance" as View,label:"출결 입력",tone:"wine"},{id:"analytics" as View,label:"운영 현황",tone:"amber"}]:[{id:"class-management" as View,label:"내 수업",tone:"blue"},{id:"schedule" as View,label:"시간표",tone:"green"},{id:"attendance" as View,label:"출결 입력",tone:"wine"},{id:"assignments" as View,label:"과제·첨삭",tone:"amber"}];
  return <section className="staff-mobile-home" aria-label="모바일 업무 홈"><div className="staff-mobile-welcome"><p>{roleLabels[role]} 홈</p><h1>{displayName}님, 안녕하세요</h1><span>오늘 필요한 학원 업무를 빠르게 확인하세요.</span></div><div className="staff-mobile-summary"><div><small>재원 학생</small><b>{studentsLoading?"…":activeStudentCount}<em>명</em></b></div><button type="button" onClick={role==="admin"?onRegister:()=>onNavigate("students")}><HansalmaeIcon name={role==="admin"?"plus":"students"} size={19}/><span>{role==="admin"?"학생 등록":"학생 보기"}</span></button></div><div className="staff-mobile-quick-links">{actions.map((item)=><button type="button" key={item.id} onClick={()=>onNavigate(item.id)}><i className={item.tone}><HansalmaeIcon name={viewIcon[item.id]} size={22}/></i><span>{item.label}</span></button>)}</div></section>;
}

function StaffBottomNavigation({role,activeView,onSelect,onMore}:{role:"admin"|"teacher";activeView:View;onSelect:(view:View)=>void;onMore:()=>void}){
  const items:{id:View;label:string}[]=role==="admin"?[{id:"dashboard",label:"홈"},{id:"students",label:"학생"},{id:"schedule",label:"시간표"},{id:"analytics",label:"학원 운영"}]:[{id:"dashboard",label:"홈"},{id:"class-management",label:"내 수업"},{id:"schedule",label:"시간표"},{id:"attendance",label:"출결"}];
  return <nav className="staff-bottom-nav" aria-label={`${roleLabels[role]} 주요 메뉴`}>{items.map(item=><button type="button" key={item.id} className={activeView===item.id?"active":""} aria-current={activeView===item.id?"page":undefined} onClick={()=>onSelect(item.id)}><HansalmaeIcon name={viewIcon[item.id]} size={21}/><span>{item.label}</span></button>)}<button type="button" onClick={onMore} aria-label="전체 메뉴 열기"><HansalmaeIcon name="menu" size={21}/><span>전체</span></button></nav>;
}

function StaffMoreSheet({items,activeView,displayName,role,onSelect,onClose,onSignOut}:{items:typeof nav;activeView:View;displayName:string;role:"admin"|"teacher";onSelect:(view:View)=>void;onClose:()=>void;onSignOut:()=>void}){
  return <div className="staff-sheet-layer" role="presentation"><button type="button" className="staff-sheet-backdrop" aria-label="전체 메뉴 닫기" onClick={onClose}/><section className="staff-more-sheet" role="dialog" aria-modal="true" aria-labelledby="staff-menu-title"><div className="staff-sheet-handle"/><header><div><p>한살매 수업노트</p><h2 id="staff-menu-title">전체 메뉴</h2></div><button type="button" onClick={onClose} aria-label="닫기">×</button></header><div className="staff-sheet-grid">{items.map(item=><button type="button" key={item.id} className={activeView===item.id?"active":""} onClick={()=>onSelect(item.id)}><i><HansalmaeIcon name={viewIcon[item.id]} size={20}/></i><span>{item.label}</span></button>)}</div><footer className="staff-sheet-account"><button type="button" className="staff-sheet-profile" onClick={()=>onSelect("my-account")}><i>{displayName.slice(0,1)}</i><span><b>{displayName}</b><small>{roleLabels[role]} 계정</small></span><em>내 계정 ›</em></button><button type="button" className="staff-sheet-signout" onClick={onSignOut}><span aria-hidden="true">↪</span><b>로그아웃</b></button></footer></section></div>;
}

function Dashboard({ supabase, profile, activeStudentCount, studentsLoading, onNavigate }: { supabase: NonNullable<ReturnType<typeof createSupabaseBrowserClient>>; profile: Profile; activeStudentCount: number; studentsLoading: boolean; onNavigate: (view: View) => void }) {
  const [live, setLive] = useState<LiveDashboard | null>(null);
  const [assignmentCount, setAssignmentCount] = useState<AssignmentCount | null>(null);
  const [consultationCount, setConsultationCount] = useState<ConsultationCount | null>(null);
  const [pauseReturns,setPauseReturns]=useState<PauseReturnAlerts|null>(null);
  const [liveError, setLiveError] = useState(false);
  useEffect(() => {
    if (profile.role === "student" || profile.role === "guardian") return;
    let active = true;
    void Promise.all([supabase.rpc("staff_dashboard_live"), supabase.rpc("assignment_dashboard_count"), supabase.rpc("consultation_dashboard_count"),supabase.rpc("staff_pause_return_alerts",{p_days:7})]).then(([dashboard, assignments, consultations,pauseAlerts]) => {
      if (!active) return;
      if (dashboard.error || !dashboard.data) setLiveError(true);
      else setLive(dashboard.data as LiveDashboard);
      if (!assignments.error && assignments.data) setAssignmentCount(assignments.data as AssignmentCount);
      if (!consultations.error && consultations.data) setConsultationCount(consultations.data as ConsultationCount);
      if (!pauseAlerts.error&&pauseAlerts.data)setPauseReturns(pauseAlerts.data as PauseReturnAlerts);
    });
    return () => { active = false; };
  }, [profile.role, supabase]);
  if (profile.role === "student" || profile.role === "guardian") {
    return <FamilyLiveDashboard supabase={supabase} profile={profile} onNavigate={onNavigate} />;
  }
  const attendance = live?.attendance;
  const nextClass = live?.todayClasses.find((item) => item.time.slice(0,5) >= new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Seoul" }));
  const attendanceMissing = Math.max(0, (live?.todayClasses.reduce((sum, item) => sum + item.enrolled, 0) ?? 0) - (attendance?.checked ?? 0));
  const urgentTotal = (assignmentCount?.total ?? 0) + (consultationCount?.overdue ?? 0) + (attendance?.makeup ?? 0);
  return <>
    <div className="page-heading"><div><p className="eyebrow">역할 · {roleLabels[profile.role]}</p><h1>안녕하세요, {profile.display_name}님</h1><p>오늘 학원 운영 현황을 한눈에 확인하세요.</p></div></div>
    <section className="stats-grid">
      <Stat label="오늘 수업" value={live ? String(live.todayClasses.length) : "…"} unit="개" detail={nextClass ? `다음 수업 ${nextClass.time.slice(0,5)}` : live ? "오늘 남은 수업 없음" : "Supabase 확인 중"} icon="▦" tone="blue" />
      <Stat label="출결 미입력" value={live ? String(attendanceMissing) : "…"} unit="명" detail={attendance?.checked ? `입력 완료 ${attendance.checked}명` : "아직 기록된 출결 없음"} icon="✓" tone="green" />
      <Stat label="확인할 과제" value={assignmentCount ? String(assignmentCount.total) : "…"} unit="건" detail={assignmentCount ? `미제출 ${assignmentCount.unsubmitted} · 첨삭 대기 ${assignmentCount.reviewPending}` : "과제 현황 확인 중"} icon="✎" tone="wine" />
      <Stat label="상담 필요" value={consultationCount ? String(consultationCount.overdue) : "…"} unit="명" detail={consultationCount ? `30일 경과 · 예정 ${consultationCount.upcoming}건` : "상담 현황 확인 중"} icon="☏" tone="amber" />
    </section>
    {pauseReturns&&(pauseReturns.overdue+pauseReturns.upcoming)>0&&<button className={`pause-return-banner${pauseReturns.overdue?" overdue":""}`} onClick={()=>onNavigate("students")}><span>↗</span><div><b>{pauseReturns.overdue?`복귀 예정일이 지난 휴원생 ${pauseReturns.overdue}명`:`7일 이내 복귀 예정 휴원생 ${pauseReturns.upcoming}명`}</b><small>{pauseReturns.students.slice(0,4).map((item)=>`${item.name} ${formatShortDate(item.expectedOn)}`).join(" · ")}</small></div><i>학생 현황에서 확인 ›</i></button>}
    <div className="dashboard-grid dashboard-focus-grid">
      <section className="panel today-panel"><PanelHeader title="오늘 수업" action="전체 시간표" onClick={() => onNavigate("schedule")} /><div className="class-list">{live?.todayClasses.map((item) => <div className="class-row" key={item.id}><time>{item.time.slice(0,5)}</time><span className="class-bar" style={{ background:item.color }} /><div className="class-info"><b>{item.name}</b><span>{item.teachers}{item.room ? ` · ${item.room}` : ""}</span></div><div className="attendance-pill"><span>출석</span><b>{item.present}/{item.enrolled}</b></div><button aria-label={`${item.name} 상세`} onClick={() => onNavigate("attendance")}>›</button></div>)}{live && live.todayClasses.length === 0 && <p className="dashboard-empty">오늘 등록된 수업이 없습니다.</p>}{!live && <p className={`dashboard-empty${liveError ? " error" : ""}`}>{liveError ? "오늘 일정을 불러오지 못했습니다." : "오늘 일정을 불러오는 중이에요…"}</p>}</div></section>
      <section className="panel attention-panel action-panel"><PanelHeader title="오늘 해야 할 일" /><p className="action-summary">지금 처리할 항목 <b>{urgentTotal}건</b></p><div className="notice-list">{notices.map((notice) => { const text = notice.label === "과제" && assignmentCount ? `미제출 ${assignmentCount.unsubmitted}건 · 첨삭 대기 ${assignmentCount.reviewPending}건` : notice.label === "상담" && consultationCount ? `30일 이상 미상담 ${consultationCount.overdue}명 · 예정 ${consultationCount.upcoming}건` : notice.label === "보강" && attendance ? `보강이 필요한 결석 기록 ${attendance.makeup}건` : notice.text; const count = notice.label === "과제" && assignmentCount ? assignmentCount.total : notice.label === "상담" && consultationCount ? consultationCount.overdue : notice.label === "보강" && attendance ? attendance.makeup : notice.count; return <button key={notice.label} onClick={() => onNavigate(notice.label === "상담" ? "consultations" : notice.label === "과제" ? "assignments" : "makeups")}><span className={`notice-icon ${notice.tone}`}>{notice.label === "상담" ? "☏" : notice.label === "과제" ? "✎" : "↻"}</span><span><b>{text}</b><small>{notice.label} 관리에서 바로 처리</small></span><strong>{count}</strong><i>›</i></button>; })}</div></section>
    </div>
    <section className="teacher-schedule-shortcuts compact" aria-label="운영 시간표 바로가기"><button onClick={() => onNavigate("schedule")}><span>▦</span><b>전과목 시간표</b><small>정규·보강·추가수업</small></button><button onClick={() => onNavigate("corrections")}><span>✎</span><b>첨삭 시간표</b><small>첨삭 배정 확인</small></button><button onClick={() => onNavigate("transport")}><span>◇</span><b>차량 운행표</b><small>탑승·하차 확인</small></button><button onClick={() => onNavigate("students")}><span className="student-shortcut-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6Zm6.5-.5a2.5 2.5 0 1 0 0-5M3.5 19c.4-3.2 2.2-5 5.5-5s5.1 1.8 5.5 5M15 14c3.1.1 4.8 1.7 5.2 4.5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg></span><b>학생 현황</b><small>재원 {studentsLoading ? "…" : activeStudentCount}명</small></button></section>
  </>;
}

function Students({ rows, allRows, total, statusFilter, loading, error, query, setQuery, onRegister, onOpen }: { rows: StudentRow[]; allRows:StudentRow[]; total: number; statusFilter:StudentStatusFilter; loading: boolean; error: string; query: string; setQuery: (value: string) => void; onRegister: () => void; onOpen: (student: StudentRow) => void }) {
  const[subject,setSubject]=useState("all");
  const[classId,setClassId]=useState("all");
  const[grade,setGrade]=useState("all");
  const[school,setSchool]=useState("all");
  const[sort,setSort]=useState<"name"|"school"|"grade"|"attendance">("name");
  const activeEnrollments=(student:StudentRow)=>student.enrollments.filter(item=>item.status==="active"&&item.classes);
  const subjects=useMemo(()=>Array.from(new Set(allRows.flatMap(getStudentSubjects))).sort((a,b)=>a.localeCompare(b,"ko")),[allRows]);
  const classes=useMemo(()=>Array.from(new Map(allRows.flatMap(student=>activeEnrollments(student)).filter(item=>subject==="all"||item.classes?.subject===subject).map(item=>[item.class_id,{id:item.class_id,name:item.classes?.name??"이름 없는 클래스",subject:item.classes?.subject??""}])).values()).sort((a,b)=>a.name.localeCompare(b.name,"ko")),[allRows,subject]);
  const grades=useMemo(()=>Array.from(new Set(allRows.map(student=>student.grade).filter((value):value is string=>Boolean(value)))).sort((a,b)=>a.localeCompare(b,"ko")),[allRows]);
  const schools=useMemo(()=>Array.from(new Set(allRows.map(student=>student.school).filter((value):value is string=>Boolean(value)))).sort((a,b)=>a.localeCompare(b,"ko")),[allRows]);
  const visible=useMemo(()=>rows.filter(student=>{
    const enrollments=activeEnrollments(student);
    return(subject==="all"||enrollments.some(item=>item.classes?.subject===subject))&&(classId==="all"||enrollments.some(item=>item.class_id===classId))&&(grade==="all"||student.grade===grade)&&(school==="all"||student.school===school);
  }).sort((a,b)=>sort==="attendance"?(b.attendanceRate??-1)-(a.attendanceRate??-1)||a.name.localeCompare(b.name,"ko"):sort==="school"?(a.school??"").localeCompare(b.school??"","ko")||a.name.localeCompare(b.name,"ko"):sort==="grade"?(a.grade??"").localeCompare(b.grade??"","ko")||a.name.localeCompare(b.name,"ko"):a.name.localeCompare(b.name,"ko")),[rows,subject,classId,grade,school,sort]);
  const selectedClass=classes.find(item=>item.id===classId);
  const hasFilters=subject!=="all"||classId!=="all"||grade!=="all"||school!=="all";
  const reset=()=>{setSubject("all");setClassId("all");setGrade("all");setSchool("all")};
  return <><div className="page-heading compact"><div><p className="eyebrow">학생 통합 관리</p><h1>학생</h1><p>학생을 누르면 개인 수업 시간표와 통합 기록을 확인할 수 있습니다.</p></div><button className="primary" onClick={onRegister}>＋ 학생 등록</button></div><section className="panel table-panel"><div className="table-tools student-list-tools"><div className="search-wrap inner"><span>⌕</span><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="이름, 학교, 과목 검색" /></div><div className="student-list-filters"><label><span>과목</span><select value={subject} onChange={event=>{setSubject(event.target.value);setClassId("all")}}><option value="all">전체 과목</option>{subjects.map(value=><option key={value}>{value}</option>)}</select></label><label><span>클래스</span><select value={classId} onChange={event=>setClassId(event.target.value)}><option value="all">전체 클래스</option>{classes.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label><span>학년</span><select value={grade} onChange={event=>setGrade(event.target.value)}><option value="all">전체 학년</option>{grades.map(value=><option key={value}>{value}</option>)}</select></label><label><span>학교</span><select value={school} onChange={event=>setSchool(event.target.value)}><option value="all">전체 학교</option>{schools.map(value=><option key={value}>{value}</option>)}</select></label><label><span>정렬</span><select value={sort} onChange={event=>setSort(event.target.value as typeof sort)}><option value="name">이름순</option><option value="school">학교순</option><option value="grade">학년순</option><option value="attendance">출석률 높은 순</option></select></label></div><strong className="student-result-count">검색 결과 {visible.length}명 <small>/ 전체 {total}명</small></strong></div>{hasFilters?<div className="student-filter-chips">{subject!=="all"&&<button onClick={()=>{setSubject("all");setClassId("all")}}>{subject} ×</button>}{classId!=="all"&&<button onClick={()=>setClassId("all")}>{selectedClass?.name??"선택 클래스"} ×</button>}{grade!=="all"&&<button onClick={()=>setGrade("all")}>{grade} ×</button>}{school!=="all"&&<button onClick={()=>setSchool("all")}>{school} ×</button>}<button className="reset" onClick={reset}>전체 초기화</button></div>:null}<div className="student-table"><div className="table-head"><span>학생</span><span>학교·학년</span><span>수강 과목</span><span>최근 30일 출석률</span><span>상태</span></div>{loading ? <StudentTableMessage>학생 데이터를 불러오는 중이에요…</StudentTableMessage> : error ? <StudentTableMessage error>{error}</StudentTableMessage> : visible.length === 0 ? <StudentTableMessage>{query||statusFilter!=="all"||hasFilters ? "선택한 조건의 학생이 없습니다." : "아직 등록된 학생이 없습니다."}</StudentTableMessage> : visible.map((student) => { const studentSubjects = getStudentSubjects(student); const normalizedStatus=normalizeStudentStatus(student.status); const hasAttendance=student.attendanceRate!==null&&student.attendanceRate!==undefined; return <button className="table-row" key={student.id} onClick={() => onOpen(student)}><span className="student-name"><i>{student.name.slice(0,1)}</i><b>{student.name}</b></span><span>{[student.school, student.grade].filter(Boolean).join(" · ") || "-"}</span><span className="subject-tags">{studentSubjects.length ? studentSubjects.map(value => <em key={value}>{value}</em>) : <em>미배정</em>}</span><strong className={hasAttendance?"attendance-rate":"attendance-rate empty"}>{hasAttendance?`${student.attendanceRate}%`:"–"}</strong><span><i className={`status ${normalizedStatus==="active"?"active":normalizedStatus==="paused"?"warning":"completed"}`}>{studentStatusLabel(student.status)}</i></span></button>; })}</div></section></>;
}

function StudentRegistrationModal({ classes,schools,onAddSchool,onDeleteSchool,onReorderSchools,onClose, onSubmit }: { classes:AcademyClass[];schools:SchoolOption[];onAddSchool:(name:string)=>Promise<string>;onDeleteSchool:(id:string)=>Promise<void>;onReorderSchools:(schools:SchoolOption[])=>Promise<void>;onClose: () => void; onSubmit: (values: StudentFormValues) => Promise<void> }) {
  const [values, setValues] = useState<StudentFormValues>({ name: "", school: "", grade: "", phone: "", guardianName: "", guardianPhone: "", residence:"", pickupLocation:"", dropoffLocation:"", status: "active", internalNote: "",classIds:[] });
  const [selectedSubjects,setSelectedSubjects]=useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [schoolManagerOpen,setSchoolManagerOpen]=useState(false);
  const [schoolAddOpen,setSchoolAddOpen]=useState(false);
  const subjects=useMemo(()=>Array.from(new Set(classes.map((item)=>item.subject))).sort((a,b)=>a.localeCompare(b,"ko")),[classes]);
  const studentGrade=gradeCode(values.grade);
  const visibleClasses=useMemo(()=>classes.filter((item)=>selectedSubjects.includes(item.subject)&&classMatchesGrade(item,studentGrade)),[classes,selectedSubjects,studentGrade]);
  const update = (field: Exclude<keyof StudentFormValues, "classIds">, value: string) => setValues((current) => field==="grade"?{...current,grade:value,classIds:current.classIds.filter((id)=>{const item=classes.find((room)=>room.id===id);return item?classMatchesGrade(item,gradeCode(value)):false;})}:{ ...current, [field]: value });
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    try {
      await onSubmit(values);
    } catch {
      setError("학생을 등록하지 못했습니다. 입력 내용을 확인하고 다시 시도해 주세요.");
      setSubmitting(false);
    }
  };
  const toggleClass=(id:string)=>setValues((current)=>({...current,classIds:current.classIds.includes(id)?current.classIds.filter((item)=>item!==id):[...current.classIds,id]}));
  const toggleSubject=(subject:string)=>{const removing=selectedSubjects.includes(subject);setSelectedSubjects((current)=>removing?current.filter((item)=>item!==subject):[...current,subject]);if(removing)setValues((current)=>({...current,classIds:current.classIds.filter((id)=>classes.find((item)=>item.id===id)?.subject!==subject)}));};
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="student-modal" role="dialog" aria-modal="true" aria-labelledby="student-registration-title"><header><div><p className="eyebrow">SUPABASE 학생 관리</p><h2 id="student-registration-title">학생 등록</h2><span>수강 과목을 먼저 고른 뒤 학생 학년에 맞는 클래스를 선택하세요.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><form onSubmit={submit}><div className="form-grid"><label>학생 이름 <b>*</b><input autoFocus required value={values.name} onChange={(event) => update("name", event.target.value)} placeholder="예: 김민준" /></label><label>학교<div className="school-select-row"><select value={values.school} onChange={(event)=>update("school",event.target.value)}><option value="">학교 선택</option>{schools.map((school)=><option value={school.name} key={school.id}>{school.name}</option>)}</select><button type="button" onClick={()=>setSchoolAddOpen(true)}>＋ 학교 추가</button><button type="button" onClick={()=>setSchoolManagerOpen(true)}>학교 관리</button></div></label><label>학년<select value={values.grade} onChange={(event)=>update("grade",event.target.value)}><option value="">학년 선택</option>{studentGrades.map((grade)=><option value={grade} key={grade}>{grade}</option>)}</select></label><label>학생 연락처<input type="tel" inputMode="numeric" maxLength={13} value={values.phone} onChange={(event) => update("phone", formatPhoneNumber(event.target.value))} placeholder="숫자만 입력" /></label><label>학부모 성함<input value={values.guardianName} onChange={(event) => update("guardianName", event.target.value)} placeholder="예: 김보호" /></label><label>학부모 연락처<input type="tel" inputMode="numeric" maxLength={13} value={values.guardianPhone} onChange={(event) => update("guardianPhone", formatPhoneNumber(event.target.value))} placeholder="숫자만 입력" /></label><label>재원 상태<select value={values.status} onChange={(event) => update("status", event.target.value)}><option value="active">재원</option><option value="paused">휴원</option><option value="completed">퇴원</option></select></label><fieldset className="registration-subject-picker full"><legend><b>1</b> 수강 과목 <small>여러 개 선택 가능</small></legend><div>{subjects.map((subject)=><button type="button" role="checkbox" aria-checked={selectedSubjects.includes(subject)} className={selectedSubjects.includes(subject)?"selected":""} key={subject} onClick={()=>toggleSubject(subject)}><span>{subject}</span><small>{classes.filter((item)=>item.subject===subject).length}개 클래스</small></button>)}{!subjects.length&&<p>등록된 과목과 클래스가 없습니다. 클래스 관리에서 먼저 만들어 주세요.</p>}</div></fieldset><fieldset className="registration-class-picker full"><legend><b>2</b> 학년에 맞는 클래스 <small>{values.grade?`${values.grade} 기준`:"학년을 선택해 주세요"}</small></legend><div>{visibleClasses.map((item)=><button type="button" role="checkbox" aria-checked={values.classIds.includes(item.id)} className={values.classIds.includes(item.id)?"selected":""} key={item.id} onClick={()=>toggleClass(item.id)}><i style={{background:item.color}}/><span><b>{item.name}</b><em>{item.subject}{gradeCode(item.name)?` · ${gradeCode(item.name)}`:" · 공통"}</em></span></button>)}{selectedSubjects.length===0&&<p>먼저 위에서 수강 과목을 선택해 주세요.</p>}{selectedSubjects.length>0&&!visibleClasses.length&&<p>{values.grade?`${values.grade}에 맞는 운영 중 클래스가 없습니다. 클래스 이름에 학년을 확인해 주세요.`:"학년을 선택하면 맞는 클래스만 표시됩니다."}</p>}</div></fieldset><label className="full">내부 메모<textarea value={values.internalNote} onChange={(event) => update("internalNote", event.target.value)} placeholder="관리자와 교사만 확인할 메모" rows={3} /></label></div>{error && <p className="form-error" role="alert">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={submitting}>{submitting ? "저장 중…" : "학생 등록"}</button></footer></form>{schoolAddOpen&&<SchoolAddModal onAdd={onAddSchool} onAdded={(name)=>{update("school",name);setSchoolAddOpen(false);}} onClose={()=>setSchoolAddOpen(false)}/>} {schoolManagerOpen&&<SchoolManager schools={schools} onDelete={onDeleteSchool} onReorder={onReorderSchools} onClose={()=>setSchoolManagerOpen(false)}/>}</section></div>;
}

function SchoolAddModal({onAdd,onAdded,onClose}:{onAdd:(name:string)=>Promise<string>;onAdded:(name:string)=>void;onClose:()=>void}){
  const[name,setName]=useState("");const[error,setError]=useState("");const[saving,setSaving]=useState(false);
  const submit=async(event:FormEvent<HTMLFormElement>)=>{event.preventDefault();const next=name.trim();if(!next){setError("학교 이름을 입력해 주세요.");return}setSaving(true);setError("");try{onAdded(await onAdd(next));}catch(nextError){setError(`학교를 추가하지 못했습니다. ${nextError instanceof Error?nextError.message:"다시 시도해 주세요."}`);setSaving(false);}};
  return <div className="modal-backdrop nested" onMouseDown={(event)=>{if(event.target===event.currentTarget)onClose();}}><section className="student-modal school-add-modal" role="dialog" aria-modal="true" aria-labelledby="school-add-title"><header><div><p className="eyebrow">학교 목록</p><h2 id="school-add-title">새 학교 추가</h2><span>학생 등록에서 선택할 학교 이름을 입력해 주세요.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><form onSubmit={submit}><label>학교 이름<input autoFocus value={name} onChange={(event)=>setName(event.target.value)} placeholder="예: 배곧중학교" /></label>{error&&<p className="form-error" role="alert">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving||!name.trim()}>{saving?"추가 중…":"학교 추가"}</button></footer></form></section></div>;
}

function SchoolManager({schools,onDelete,onReorder,onClose}:{schools:SchoolOption[];onDelete:(id:string)=>Promise<void>;onReorder:(schools:SchoolOption[])=>Promise<void>;onClose:()=>void}){
  const[items,setItems]=useState(schools);const[error,setError]=useState("");const[saving,setSaving]=useState(false);
  useEffect(()=>setItems(schools),[schools]);
  const sortable=useSortableOrder((activeId,overId)=>setItems((current)=>reorderById(current,activeId,overId)));
  const save=async()=>{setSaving(true);setError("");try{await onReorder(items);onClose();}catch(next){setError(next instanceof Error?next.message:"학교 순서를 저장하지 못했습니다.");setSaving(false);}};
  const remove=async(item:SchoolOption)=>{if(!window.confirm(`${item.name} 학교를 목록에서 삭제할까요?`))return;setError("");try{await onDelete(item.id);setItems((current)=>current.filter((school)=>school.id!==item.id));}catch(next){setError(next instanceof Error?next.message:"학교를 삭제하지 못했습니다.");}};
  return <div className="modal-backdrop nested"><section className="student-modal school-manager" role="dialog" aria-modal="true"><header><div><p className="eyebrow">개인별 학교 목록</p><h2>학교 관리</h2><span>끌어서 순서를 바꾸세요. 모바일에서는 손잡이를 길게 누른 뒤 이동합니다.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><div className="sortable-settings-list">{items.map((item)=><article key={item.id} {...sortable.itemProps(item.id)} className={sortable.draggingId===item.id?"dragging":""}><button type="button" data-drag-handle aria-label={`${item.name} 순서 이동`}>☷</button><b>{item.name}</b><button type="button" className="danger" onClick={()=>void remove(item)}>삭제</button></article>)}</div>{error&&<p className="form-error">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button type="button" className="primary" disabled={saving} onClick={()=>void save()}>{saving?"저장 중…":"내 순서 저장"}</button></footer></section></div>;
}

const studentGrades=["초6","중1","중2","중3","고1","고2","고3","재수","검정고시"];
function gradeCode(value:string){return value.replace(/\s/g,"").match(/(?:초6|중[1-3]|고[1-3]|재수|검정고시)/)?.[0]??"";}
function classMatchesGrade(item:AcademyClass,studentGrade:string){const roomGrade=gradeCode(item.name);return !studentGrade||!roomGrade||roomGrade===studentGrade;}

function ClassRegistrationModal({ subjects,onClose, onSubmit }: { subjects:SubjectOption[];onClose: () => void; onSubmit: (values: ClassFormValues) => Promise<void> }) {
  const [values, setValues] = useState<ClassFormValues>(()=>{const first=subjects[0];return{ name: "", subject:first?.name??"",subjectId:first?.id??"", room: "", color: "#922D61" }});
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setSubmitting(true); setError("");
    try { await onSubmit(values); } catch { setError("클래스를 등록하지 못했습니다. 다시 시도해 주세요."); setSubmitting(false); }
  };
  return <ModalShell eyebrow="SUPABASE 수업 관리" title="클래스 등록" description="기본 과목 또는 담당 선생님이 만든 하위과목을 선택합니다." onClose={onClose}><form onSubmit={submit}><div className="form-grid"><label>클래스 이름 <b>*</b><input autoFocus required value={values.name} onChange={(event) => setValues({ ...values, name: event.target.value })} placeholder="예: 고3 미적분 A" /></label><label>과목 <b>*</b><select required value={values.subjectId} onChange={(event)=>{const selected=subjects.find((item)=>item.id===event.target.value);setValues({...values,subjectId:event.target.value,subject:selected?.name??""});}}>{(["국어","영어","수학"] as const).map((main)=><optgroup label={main} key={main}>{subjects.filter((item)=>item.main_subject===main).map((item)=><option key={item.id} value={item.id}>{item.name}</option>)}</optgroup>)}</select></label><label>강의실<input value={values.room} onChange={(event) => setValues({ ...values, room: event.target.value })} placeholder="예: A 강의실" /></label><label>표시 색상<input type="color" value={values.color} onChange={(event) => setValues({ ...values, color: event.target.value })} /></label></div>{error && <p className="form-error">{error}</p>}<ModalActions onClose={onClose} submitting={submitting} submitLabel="클래스 등록" disabled={!values.subjectId}/></form></ModalShell>;
}

type StudentScheduleChoice={scheduleId:string;classId:string;className:string;subject:string;color:string;weekday:number;startTime:string;endTime:string;assigned:boolean};
function EnrollmentModal({ supabase,student, classes, onClose, onSubmit }: { supabase:SupabaseClient;student: StudentRow; classes: AcademyClass[]; onClose: () => void; onSubmit: (classIds: string[]) => Promise<void> }) {
  const assigned = new Set(student.enrollments.filter((item) => item.status === "active").map((item) => item.class_id));
  const [classIds, setClassIds] = useState([...assigned]);
  const [scheduleChoices,setScheduleChoices]=useState<StudentScheduleChoice[]>([]);
  const [scheduleIds,setScheduleIds]=useState<string[]>([]);
  const [step,setStep]=useState<"classes"|"schedules">("classes");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const loadSchedules=async()=>{const{data,error:loadError}=await supabase.rpc("staff_student_schedule_choices",{p_student_id:student.id});if(loadError)throw loadError;const rows=(data??[]) as StudentScheduleChoice[];setScheduleChoices(rows);setScheduleIds(rows.filter((item)=>item.assigned).map((item)=>item.scheduleId));setStep("schedules");};
  const submit = async (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); setSubmitting(true); setError(""); try { if(step==="classes"){await onSubmit(classIds);await loadSchedules();}else{const{error:saveError}=await supabase.rpc("staff_save_student_schedule_assignments",{p_student_id:student.id,p_schedule_ids:scheduleIds});if(saveError)throw saveError;onClose();} } catch(next) { setError(next instanceof Error?next.message:"수강 정보를 저장하지 못했습니다."); } finally {setSubmitting(false);} };
  const toggle=(id:string)=>setClassIds((current)=>current.includes(id)?current.filter((item)=>item!==id):[...current,id]);
  const toggleSchedule=(id:string)=>setScheduleIds((current)=>current.includes(id)?current.filter((item)=>item!==id):[...current,id]);
  return <ModalShell eyebrow="학생 수강 관리" title={`${student.name} · 과목과 반 수정`} description={step==="classes"?"한 학생에게 여러 과목·세부 반을 동시에 배정합니다.":"실제로 참석하는 요일별 반을 선택하세요. 선택하지 않으면 기존처럼 모든 수강 반에 표시됩니다."} onClose={onClose}><form onSubmit={submit}>{step==="classes"?(classes.length ? <div className="class-choice-list">{classes.map((item) => <label key={item.id} className={classIds.includes(item.id) ? "selected" : ""}><input type="checkbox" checked={classIds.includes(item.id)} onChange={() => toggle(item.id)} /><i style={{ background:item.color }} /><span><b>{item.name}</b><small>{item.subject}{item.room ? ` · ${item.room}` : ""}</small></span></label>)}</div> : <p className="modal-empty">등록된 클래스가 없습니다.</p>):<div className="schedule-choice-list">{scheduleChoices.map((item)=><button type="button" key={item.scheduleId} className={scheduleIds.includes(item.scheduleId)?"selected":""} onClick={()=>toggleSchedule(item.scheduleId)}><i style={{background:item.color}}/><span><b>{["월","화","수","목","금","토","일"][item.weekday-1]} · {item.className}</b><small>{item.subject} · {item.startTime.slice(0,5)}–{item.endTime.slice(0,5)}</small></span></button>)}{!scheduleChoices.length&&<p className="modal-empty">선택한 클래스에 등록된 수업 시간이 없습니다.</p>}</div>}{error && <p className="form-error">{error}</p>}<footer>{step==="schedules"?<button type="button" className="secondary-button" onClick={()=>setStep("classes")}>이전</button>:<button type="button" className="secondary-button" onClick={onClose}>취소</button>}<button className="primary" disabled={submitting}>{submitting?"저장 중…":step==="classes"?"반 저장 후 요일 배정":"교차수강 배정 저장"}</button></footer></form></ModalShell>;
}

function ModalShell({ eyebrow, title, description, onClose, children }: { eyebrow: string; title: string; description: string; onClose: () => void; children: ReactNode }) {
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="student-modal" role="dialog" aria-modal="true"><header><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2><span>{description}</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header>{children}</section></div>;
}

function ModalActions({ onClose, submitting, submitLabel, disabled = false }: { onClose: () => void; submitting: boolean; submitLabel: string; disabled?: boolean }) {
  return <footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={submitting || disabled}>{submitting ? "저장 중…" : submitLabel}</button></footer>;
}

function StudentTableMessage({ children, error = false }: { children: string; error?: boolean }) {
  return <div className={`student-table-message${error ? " error" : ""}`}>{children}</div>;
}

function getStudentSubjects(student: StudentRow) {
  return [...new Set(student.enrollments.filter((item) => item.status === "active").map((item) => item.classes?.subject).filter((subject): subject is string => Boolean(subject)))];
}

function isActiveStudent(student: StudentRow) {
  return student.status === "active" || student.status === "재원";
}

function normalizeStudentStatus(status:string):Exclude<StudentStatusFilter,"all"> {
  return status==="active"||status==="재원"?"active":status==="paused"||status==="휴원"?"paused":"completed";
}

function formatShortDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"short",day:"numeric"}).format(new Date(value))}

function studentStatusLabel(status: string) {
  return ({ active: "재원", paused: "휴원", completed: "퇴원" } as Record<string, string>)[status] ?? status;
}

function Schedule({ classes, onRegister }: { classes: AcademyClass[]; onRegister: () => void }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">수업 운영</p><h1>클래스</h1><p>Supabase에 클래스를 등록하고 학생에게 수강 과목을 배정합니다.</p></div><button className="primary" onClick={onRegister}>＋ 클래스 등록</button></div><section className="panel class-panel"><div className="panel-header"><h2>운영 클래스</h2><span>전체 {classes.length}개</span></div>{classes.length ? <div className="academy-class-grid">{classes.map((item) => <article key={item.id}><i style={{ background:item.color }} /><div><b>{item.name}</b><span>{item.subject}{item.room ? ` · ${item.room}` : ""}</span></div><em>운영 중</em></article>)}</div> : <div className="modal-empty">아직 등록된 클래스가 없습니다. 위의 클래스 등록 버튼을 눌러 시작하세요.</div>}</section></>;
}

function SimplePanel({ title, description, items }: { title: string; description: string; items: string[] }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">한살매 관리</p><h1>{title}</h1><p>{description}</p></div><button className="primary">＋ 새 기록</button></div><section className="panel simple-panel"><h2>오늘 확인할 항목</h2>{items.map((item, index) => <button key={item}><span>{index + 1}</span><b>{item}</b><i>›</i></button>)}</section></>;
}

function AuthBrand({compact=false}:{compact?:boolean}){
  return <div className={`auth-brand-lockup${compact?" compact":""}`}><img src="/hansalmae-logo.png" alt="한살매 로고"/><p><strong>한살매</strong><span>수업노트</span></p></div>;
}

function LoginScreen({ supabase,onSubmit, error }: { supabase:SupabaseClient;onSubmit: (email: string, password: string) => Promise<void>; error: string }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [rememberEmail, setRememberEmail] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [signup,setSignup]=useState(false);
  useEffect(() => {
    const savedEmail = window.localStorage.getItem("hansalmae-saved-email");
    if (!savedEmail) return;
    setEmail(savedEmail);
    setRememberEmail(true);
  }, []);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const normalizedEmail = email.trim();
    if (rememberEmail) window.localStorage.setItem("hansalmae-saved-email", normalizedEmail);
    else window.localStorage.removeItem("hansalmae-saved-email");
    setSubmitting(true);
    await onSubmit(normalizedEmail, password);
    setSubmitting(false);
  };
  if(signup)return <InviteSignup supabase={supabase} onBack={()=>setSignup(false)}/>;
  return <main className="auth-shell"><section className="auth-card login-card"><AuthBrand/><p className="auth-copy">수업과 학습 기록을 한곳에서 확인하세요.</p><form onSubmit={submit}><label>이메일<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required placeholder="name@example.com" /></label><label>비밀번호<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" required placeholder="비밀번호" /></label><label className="remember-email"><input type="checkbox" checked={rememberEmail} onChange={(event) => setRememberEmail(event.target.checked)} /><span>아이디 저장</span></label>{error && <p className="auth-error" role="alert">{error}</p>}<button className="primary" disabled={submitting}>{submitting ? "로그인 중…" : "로그인"}</button></form><div className="auth-divider"><span>처음 이용하시나요?</span></div><button className="auth-signup-link" onClick={()=>setSignup(true)}>초대코드로 회원가입</button><small>초대코드는 학원 관리자에게 문의해 주세요.</small></section></main>;
}

function InviteSignup({supabase,onBack}:{supabase:SupabaseClient;onBack:()=>void}){
 const [step,setStep]=useState<1|2|3>(1),[code,setCode]=useState(""),[role,setRole]=useState(""),[targetName,setTargetName]=useState(""),[email,setEmail]=useState(""),[password,setPassword]=useState(""),[confirm,setConfirm]=useState(""),[displayName,setDisplayName]=useState(""),[phone,setPhone]=useState(""),[loading,setLoading]=useState(false),[message,setMessage]=useState("");
 const invoke=async(body:Record<string,unknown>)=>{const{data,error}=await supabase.functions.invoke("invite-signup",{body});if(error){let text=error.message;const context=(error as{context?:Response}).context;if(context)try{const json=await context.clone().json() as{error?:string};if(json.error)text=json.error}catch{}throw new Error(text)}return data as Record<string,unknown>};
 const check=async(event:FormEvent)=>{event.preventDefault();setLoading(true);setMessage("");try{const data=await invoke({action:"check",code});setRole(String(data.role));setTargetName(String(data.targetName));setStep(2)}catch(next){setMessage(next instanceof Error?next.message:"초대코드를 확인해 주세요.")}setLoading(false)};
 const register=async(event:FormEvent)=>{event.preventDefault();if(password!==confirm){setMessage("비밀번호가 서로 일치하지 않습니다.");return}setLoading(true);setMessage("");try{await invoke({action:"register",code,email,password,displayName,phone});setStep(3)}catch(next){setMessage(next instanceof Error?next.message:"회원가입을 완료하지 못했습니다.")}setLoading(false)};
 const normalized=code.toUpperCase().replace(/[^A-Z0-9]/g,"").slice(0,8);
 const steps=["초대 확인","정보 입력","가입 완료"];
 return <main className="auth-shell"><section className="auth-card signup-card"><button className="signup-back" aria-label={step===1?"로그인으로 돌아가기":"초대코드 입력으로 돌아가기"} onClick={step===1?onBack:()=>{setStep(1);setMessage("")}}>‹</button><AuthBrand compact/><header className="signup-heading"><p className="signup-eyebrow">초대 회원가입</p><h1>{step===3?"가입이 완료됐어요":"내 계정 만들기"}</h1></header><ol className="signup-progress" aria-label="회원가입 진행 단계">{steps.map((label,index)=>{const order=index+1;return <li key={label} className={`${step===order?"current ":""}${step>=order?"active":""}`}><i>{step>order?"✓":order}</i><span>{label}</span></li>})}</ol>{step===1&&<div className="signup-step-content"><p className="auth-copy">학원에서 받은 8자리 초대코드를 입력해 주세요.</p><form onSubmit={check}><label>초대코드<input className="invite-code-input" value={normalized.length>4?`${normalized.slice(0,4)}-${normalized.slice(4)}`:normalized} onChange={event=>setCode(event.target.value)} autoCapitalize="characters" autoComplete="one-time-code" placeholder="ABCD-EFGH" required/></label>{message&&<p className="auth-error">{message}</p>}<button className="primary" disabled={loading||normalized.length!==8}>{loading?"확인 중…":"초대코드 확인"}</button></form></div>}{step===2&&<div className="signup-step-content"><section className="signup-target"><span>{role==="student"?"학생":role==="guardian"?"학부모":"선생님"} 계정</span><b>{targetName}</b><small>이 연결 정보는 가입 후 자동으로 적용됩니다.</small></section><form onSubmit={register}><label>이름<input required value={displayName} onChange={event=>setDisplayName(event.target.value)} placeholder="실명을 입력해 주세요"/></label><label>이메일<input required type="email" autoComplete="email" value={email} onChange={event=>setEmail(event.target.value)} placeholder="name@example.com"/></label>{role==="guardian"&&<label>연락처<input required inputMode="tel" value={phone} onChange={event=>setPhone(formatPhoneNumber(event.target.value))} placeholder="010-0000-0000"/></label>}<div className="signup-passwords"><label>비밀번호<input required minLength={8} type="password" autoComplete="new-password" value={password} onChange={event=>setPassword(event.target.value)} placeholder="8자 이상"/></label><label>비밀번호 확인<input required minLength={8} type="password" autoComplete="new-password" value={confirm} onChange={event=>setConfirm(event.target.value)} placeholder="한 번 더 입력"/></label></div>{message&&<p className="auth-error">{message}</p>}<button className="primary" disabled={loading}>{loading?"가입 중…":"회원가입 완료"}</button></form></div>}{step===3&&<div className="signup-complete"><i>✓</i><p className="auth-copy">등록한 이메일과 비밀번호로<br/>바로 로그인할 수 있습니다.</p><button className="primary signup-finish" onClick={onBack}>로그인하러 가기</button></div>}</section></main>
}

function LoadingScreen() { return <main className="auth-shell"><section className="auth-card loading"><img src="/hansalmae-logo.png" alt="" /><p>로그인 정보를 확인하고 있어요…</p></section></main>; }
function ConfigurationScreen() { return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>연결 설정이 필요합니다</h1><p className="auth-copy">Supabase 공개 URL과 anon key를 환경 변수에 등록해 주세요.</p></section></main>; }
function AccessPendingScreen({ email, error, onSignOut }: { email: string; error: string; onSignOut: () => void }) { return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>접근 권한 확인</h1><p className="auth-copy">{error || `${email} 계정에 아직 역할이 지정되지 않았습니다.`}</p><button className="secondary-button" onClick={onSignOut}>다른 계정으로 로그인</button></section></main>; }

function Stat({ label, value, unit, detail, icon, tone }: { label: string; value: string; unit: string; detail: string; icon: string; tone: string }) { return <article className="stat-card"><div className={`stat-icon ${tone}`}>{icon}</div><div><span>{label}</span><p><strong>{value}</strong> {unit}</p><small>{detail}</small></div></article>; }
function PanelHeader({ title, action, onClick }: { title: string; action?: string; onClick?: () => void }) { return <div className="panel-header"><h2>{title}</h2>{action && <button onClick={onClick}>{action} <span>›</span></button>}</div>; }
function Activity({ icon, tone, title, meta }: { icon: string; tone: string; title: string; meta: string }) { return <div className="activity"><span className={`notice-icon ${tone}`}>{icon}</span><div><b>{title}</b><small>{meta}</small></div></div>; }
