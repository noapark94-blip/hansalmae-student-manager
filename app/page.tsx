"use client";

import type { FormEvent, ReactNode } from "react";
import { useEffect, useMemo, useState } from "react";
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
import { OperationsAuditBoard } from "./operations-audit";
import { StudentLifecycleDashboard, type StudentStatusFilter } from "./student-lifecycle-dashboard";
import { NotificationCenter } from "./notification-center";
import { TuitionBoard } from "./tuition-board";
import { TuitionRulesBoard } from "./tuition-rules-board";
import { OperationsAnalytics } from "./operations-analytics";
import { BackupBoard } from "./backup-board";
import { BulkImportBoard } from "./bulk-import-board";
import { BulkAccountBoard } from "./bulk-account-board";
import { SidebarNavigation } from "./sidebar-navigation";
import { reorderById, useSortableOrder } from "./use-sortable-order";
import { BulkRegistrationGuide } from "./bulk-registration-guide";
import { TeacherClassWorkspace } from "./teacher-class-workspace";
import { WeeklyTimetable, type WeeklyTimetableRow } from "./weekly-timetable";

export type View = "dashboard" | "students" | "bulk-import" | "bulk-accounts" | "guide" | "class-management" | "schedule" | "corrections" | "transport" | "attendance" | "makeups" | "assignments" | "consultations" | "communications" | "tuition" | "tuition-settings" | "analytics" | "backup" | "settings" | "my-account" | "audit";
type StudentFormValues = { name: string; school: string; grade: string; phone: string; guardianName: string; guardianPhone: string; status: string; internalNote: string; classIds:string[] };
type StudentDetails = { id: string; name: string; school: string; grade: string; phone: string; status: string; internalNote: string };
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
  { id: "tuition", label: "수납·미납", icon: "₩" },
  { id: "tuition-settings", label: "수강료 설정", icon: "₩" },
  { id: "analytics", label: "운영 통계", icon: "▥" },
  { id: "backup", label: "데이터 백업", icon: "⇩" },
  { id: "audit", label: "운영 점검", icon: "◉" },
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
  admin: ["dashboard", "students", "bulk-import", "bulk-accounts", "guide", "class-management", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "communications", "tuition", "tuition-settings", "analytics", "backup", "settings", "my-account", "audit"],
  teacher: ["dashboard", "students", "guide", "class-management", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "communications", "tuition", "tuition-settings", "my-account"],
  student: ["dashboard", "schedule", "attendance", "makeups", "assignments", "communications", "tuition", "my-account"],
  guardian: ["dashboard", "schedule", "attendance", "makeups", "consultations", "communications", "tuition", "my-account"],
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
  const [view, setView] = useState<View>("dashboard");
  const [query, setQuery] = useState("");
  const [searchOpen,setSearchOpen]=useState(false);
  const [adminHomeMode,setAdminHomeMode]=useState<"operations"|"classes">("operations");
  const [mobileNav, setMobileNav] = useState(false);
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
    if (!supabase) {
      return;
    }

    const loadProfile = async (nextUser: User | null) => {
      setAuthReady(false);
      setUser(nextUser);
      if (!nextUser) {
        setProfile(null);
        setAuthError("");
        setAuthReady(true);
        return;
      }

      const [{ data: role, error }, { data: ownProfile }] = await Promise.all([
        supabase.rpc("current_user_role"),
        supabase.from("profiles").select("display_name").eq("id", nextUser.id).maybeSingle(),
      ]);

      if (error || !role || !roleViews[role as UserRole]) {
        setAuthError("계정 역할을 확인할 수 없습니다. 관리자에게 문의해 주세요.");
        setProfile(null);
      } else {
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
      void loadProfile(session?.user ?? null);
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
      const [{ data, error }, { data: classData, error: classError },{data:subjectData,error:subjectError},{data:timetableData,error:timetableError}] = await Promise.all([
        supabase.rpc("staff_student_roster"),
        supabase.from("classes").select("id, name, subject, subject_id, room, color, active").eq("active", true).order("name"),
        supabase.from("academy_subjects").select("id,name,main_subject,parent_id").eq("active",true).order("main_subject").order("name"),
        supabase.rpc("staff_student_weekly_timetables"),
      ]);

      if (!active) return;
      if (error || classError || subjectError || timetableError) {
        setStudentsError("학생 데이터를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.");
        setStudents([]);
      } else {
        setStudents(((data ?? []) as StudentRow[]).sort((a, b) => a.name.localeCompare(b.name, "ko")));
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
    setQuery("");
    setSearchOpen(false);
  };

  if (!authReady) return <LoadingScreen />;
  if (!supabase) return <ConfigurationScreen />;
  if (!user) return <LoginScreen onSubmit={async (email, password) => {
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
    const { data, error } = await supabase.from("students").select("id, name, school, grade, phone, status, internal_note").eq("id", student.id).single();
    if (error) { showToast("학생 상세 정보를 불러오지 못했습니다."); return; }
    setStudentDetails({ id: data.id, name: data.name, school: data.school ?? "", grade: data.grade ?? "", phone: data.phone ?? "", status: data.status, internalNote: data.internal_note ?? "" });
  };

  const updateStudent = async (values: StudentDetails) => {
    const { data, error } = await supabase.from("students").update({ name: values.name.trim(), school: values.school.trim() || null, grade: values.grade.trim() || null, phone: values.phone.trim() || null, status: values.status, internal_note: values.internalNote.trim() || null }).eq("id", values.id).select("id, name, school, grade, status").single();
    if (error) throw error;
    setStudents((current) => current.map((student) => student.id === values.id ? { ...student, ...data } : student).sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setStudentDetails(null);
    showToast(`${data.name} 학생 정보를 수정했습니다.`);
  };

  const deleteStudent = async (student: StudentDetails) => {
    const { error } = await supabase.from("students").delete().eq("id", student.id);
    if (error) throw error;
    setStudents((current) => current.filter((item) => item.id !== student.id));
    setStudentDetails(null);
    showToast(`${student.name} 학생을 삭제했습니다.`);
  };

  return (
    <main className="app-shell">
      <aside className={`sidebar ${mobileNav ? "is-open" : ""}`}>
        <button className="brand" type="button" onClick={() => selectView("dashboard")} aria-label="홈으로 이동">
          <img className="brand-mark" src="/hansalmae-logo.png" alt="한살매 로고" />
          <div><strong>한살매</strong><span>학생관리</span></div>
        </button>
        <SidebarNavigation supabase={supabase} role={profile.role} items={allowedNav} activeView={view} onSelect={selectView} />
        <div className="sidebar-bottom">
          <div className="teacher-card"><div className="avatar">{profile.display_name.slice(0, 1)}</div><div><b>{profile.display_name}</b><span>{roleLabels[profile.role]}</span></div><button className="signout-button" onClick={() => void supabase.auth.signOut()}>로그아웃</button></div>
        </div>
      </aside>

      {mobileNav && <button className="backdrop" aria-label="메뉴 닫기" onClick={() => setMobileNav(false)} />}

      <section className="workspace">
        <header className="topbar">
          <button className="menu-button" aria-label="메뉴 열기" onClick={() => setMobileNav(true)}>☰</button>
          <div className="global-search"><div className="search-wrap"><span>⌕</span><input value={query} onFocus={()=>setSearchOpen(true)} onChange={(event) => {setQuery(event.target.value);setSearchOpen(true);}} onKeyDown={(event)=>{if(event.key==="Escape")setSearchOpen(false);if(event.key==="Enter"){const firstStudent=globalSearch.students[0];const firstClass=globalSearch.classes[0];if(firstStudent){void openStudentDetails(firstStudent);setSearchOpen(false);}else if(firstClass){selectView("schedule");showToast(`${firstClass.name} 클래스를 시간표에서 확인해 주세요.`);}}}} placeholder="학생, 클래스 검색" /></div>{searchOpen&&query.trim()&&<div className="global-search-results">{globalSearch.students.map((student)=><button key={student.id} onClick={()=>{void openStudentDetails(student);setSearchOpen(false);}}><i>人</i><span><b>{student.name}</b><small>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생"}</small></span><em>학생 보기</em></button>)}{globalSearch.classes.map((item)=><button key={item.id} onClick={()=>{selectView("schedule");showToast(`${item.name} 클래스를 시간표에서 확인해 주세요.`);}}><i style={{color:item.color}}>▦</i><span><b>{item.name}</b><small>{item.subject}{item.room?` · ${item.room}`:""}</small></span><em>시간표 보기</em></button>)}{!globalSearch.students.length&&!globalSearch.classes.length&&<p>검색 결과가 없습니다.</p>}</div>}</div>
          <NotificationCenter supabase={supabase} />
          {(profile.role === "admin" || profile.role === "teacher") && <button className="primary small" onClick={() => void refreshStudentRegistrationCatalog().then((ready)=>ready&&setRegistrationOpen(true))}>＋ 학생 등록</button>}
        </header>

        <div className="content">
          {view === "dashboard" && profile.role==="admin"&&<><div className="admin-home-switch"><button className={adminHomeMode==="operations"?"active":""} onClick={()=>setAdminHomeMode("operations")}>학원 운영</button><button className={adminHomeMode==="classes"?"active":""} onClick={()=>setAdminHomeMode("classes")}>내 수업</button></div>{adminHomeMode==="operations"?<Dashboard supabase={supabase} profile={profile} activeStudentCount={students.filter(isActiveStudent).length} studentsLoading={studentsLoading} onNavigate={selectView}/>:<TeacherClassWorkspace supabase={supabase} profile={profile} onClassesChanged={()=>void refreshStudentRegistrationCatalog()}/>}</>}
          {view === "dashboard" && profile.role==="teacher"&&<TeacherClassWorkspace supabase={supabase} profile={profile} onClassesChanged={()=>void refreshStudentRegistrationCatalog()}/>}
          {view === "dashboard" && (profile.role==="student"||profile.role==="guardian")&&<Dashboard supabase={supabase} profile={profile} activeStudentCount={students.filter(isActiveStudent).length} studentsLoading={studentsLoading} onNavigate={selectView}/>}
          {view === "students" && <><StudentLifecycleDashboard supabase={supabase} filter={studentStatusFilter} onFilter={setStudentStatusFilter}/><Students rows={filteredStudents} timetables={studentTimetables} total={students.length} filteredTotal={filteredStudents.length} statusFilter={studentStatusFilter} loading={studentsLoading} error={studentsError} query={query} setQuery={setQuery} onRegister={() => void refreshStudentRegistrationCatalog().then((ready)=>ready&&setRegistrationOpen(true))} onOpen={openStudentDetails} /></>}
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
          {view === "tuition-settings" && <TuitionRulesBoard supabase={supabase} />}
          {view === "analytics" && <OperationsAnalytics supabase={supabase} />}
          {view === "backup" && <BackupBoard supabase={supabase} />}
          {view === "settings" && <><SettingsBoard supabase={supabase} /><AccountDeletionPanel supabase={supabase} /></>}
          {view === "audit" && <OperationsAuditBoard supabase={supabase} onNavigate={selectView} />}
          {view === "my-account" && <MyAccount supabase={supabase} profile={profile} email={user.email ?? ""} onProfileUpdated={(displayName) => setProfile((current) => current ? { ...current, display_name:displayName } : current)} />}
        </div>
      </section>
      {registrationOpen && <StudentRegistrationModal classes={academyClasses} schools={academySchools} onAddSchool={addRegistrationSchool} onDeleteSchool={deleteRegistrationSchool} onReorderSchools={reorderRegistrationSchools} onClose={() => setRegistrationOpen(false)} onSubmit={registerStudent} />}
      {classRegistrationOpen && <ClassRegistrationModal subjects={academySubjects} onClose={() => setClassRegistrationOpen(false)} onSubmit={registerClass} />}
      {enrollmentStudent && <EnrollmentModal supabase={supabase} student={enrollmentStudent} classes={academyClasses} onClose={() => setEnrollmentStudent(null)} onSubmit={(classIds) => saveClassAssignments(enrollmentStudent, classIds)} />}
      {studentDetails && <StudentDetailHub supabase={supabase} student={studentDetails} rosterStudent={students.find((item) => item.id === studentDetails.id)} onClose={() => setStudentDetails(null)} onUpdate={updateStudent} onDelete={deleteStudent} onAssign={(student) => { setStudentDetails(null); setEnrollmentStudent(student as StudentRow); }} onLifecycleUpdated={(status) => { setStudentDetails((current) => current ? { ...current, status } : current); setStudents((current) => current.map((item) => item.id === studentDetails.id ? { ...item, status, enrollments:status === "active" ? item.enrollments : item.enrollments.map((enrollment) => enrollment.status === "active" ? { ...enrollment, status:status === "paused" ? "paused" : "completed" } : enrollment) } : item)); }} />}
      {toast && <div className="toast" role="status">{toast}</div>}
    </main>
  );
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
  const attendanceRate = attendance?.checked ? Math.round((attendance.present / attendance.checked) * 100) : null;
  const nextClass = live?.todayClasses.find((item) => item.time.slice(0,5) >= new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Seoul" }));
  const weekTotals = (live?.weekAttendance ?? []).reduce((total, day) => ({ present: total.present + day.present, late: total.late + day.late, absent: total.absent + day.absent }), { present: 0, late: 0, absent: 0 });
  return <>
    <div className="page-heading"><div><p className="eyebrow">역할 · {roleLabels[profile.role]}</p><h1>안녕하세요, {profile.display_name}님</h1><p>오늘 학원 운영 현황을 한눈에 확인하세요.</p></div><button className="primary" onClick={() => onNavigate("communications")}>✦ 새 공지 작성</button></div>
    <section className="stats-grid">
      <Stat label="전체 재원생" value={studentsLoading ? "…" : String(activeStudentCount)} unit="명" detail="Supabase 실시간 기준" icon="人" tone="wine" />
      <Stat label="오늘 수업" value={live ? String(live.todayClasses.length) : "…"} unit="개" detail={nextClass ? `다음 수업 ${nextClass.time.slice(0,5)}` : live ? "오늘 남은 수업 없음" : "Supabase 확인 중"} icon="▦" tone="blue" />
      <Stat label="오늘 출석률" value={attendanceRate === null ? "–" : String(attendanceRate)} unit={attendanceRate === null ? "" : "%"} detail={attendance?.checked ? `출석 ${attendance.present} · 지각 ${attendance.late} · 결석 ${attendance.absent}` : "아직 기록된 출결 없음"} icon="✓" tone="green" />
      <Stat label="확인할 항목" value={attendance ? String(attendance.makeup) : "…"} unit="건" detail="보강 필요 출결 기준" icon="!" tone="amber" />
    </section>
    <section className="teacher-schedule-shortcuts" aria-label="선생님 시간표 바로가기"><button onClick={() => onNavigate("schedule")}><span>▦</span><b>학원 전과목 시간표</b><small>공동담당·개인 시간표 연동</small></button><button onClick={() => onNavigate("corrections")}><span>✎</span><b>첨삭 시간표</b><small>월–금 90분 고정 슬롯</small></button><button onClick={() => onNavigate("transport")}><span>◇</span><b>차량 운행 시간표</b><small>차량실장님·탑승 위치·학생</small></button></section>
    {pauseReturns&&(pauseReturns.overdue+pauseReturns.upcoming)>0&&<button className={`pause-return-banner${pauseReturns.overdue?" overdue":""}`} onClick={()=>onNavigate("students")}><span>↗</span><div><b>{pauseReturns.overdue?`복귀 예정일이 지난 휴원생 ${pauseReturns.overdue}명`:`7일 이내 복귀 예정 휴원생 ${pauseReturns.upcoming}명`}</b><small>{pauseReturns.students.slice(0,4).map((item)=>`${item.name} ${formatShortDate(item.expectedOn)}`).join(" · ")}</small></div><i>학생 현황에서 확인 ›</i></button>}
    <div className="dashboard-grid">
      <section className="panel today-panel"><PanelHeader title="오늘 수업" action="전체 시간표" onClick={() => onNavigate("schedule")} /><div className="class-list">{live?.todayClasses.map((item) => <div className="class-row" key={item.id}><time>{item.time.slice(0,5)}</time><span className="class-bar" style={{ background:item.color }} /><div className="class-info"><b>{item.name}</b><span>{item.teachers}{item.room ? ` · ${item.room}` : ""}</span></div><div className="attendance-pill"><span>출석</span><b>{item.present}/{item.enrolled}</b></div><button aria-label={`${item.name} 상세`} onClick={() => onNavigate("attendance")}>›</button></div>)}{live && live.todayClasses.length === 0 && <p className="dashboard-empty">오늘 등록된 수업이 없습니다.</p>}{!live && <p className={`dashboard-empty${liveError ? " error" : ""}`}>{liveError ? "오늘 일정을 불러오지 못했습니다." : "오늘 일정을 불러오는 중이에요…"}</p>}</div></section>
      <section className="panel attention-panel"><PanelHeader title="지금 확인해 주세요" /><div className="notice-list">{notices.map((notice) => { const text = notice.label === "과제" && assignmentCount ? `미제출 ${assignmentCount.unsubmitted}건 · 첨삭 대기 ${assignmentCount.reviewPending}건` : notice.label === "상담" && consultationCount ? `30일 이상 미상담 ${consultationCount.overdue}명 · 예정 ${consultationCount.upcoming}건` : notice.label === "보강" && attendance ? `보강이 필요한 결석 기록 ${attendance.makeup}건` : notice.text; const count = notice.label === "과제" && assignmentCount ? assignmentCount.total : notice.label === "상담" && consultationCount ? consultationCount.overdue : notice.label === "보강" && attendance ? attendance.makeup : notice.count; return <button key={notice.label} onClick={() => onNavigate(notice.label === "상담" ? "consultations" : notice.label === "과제" ? "assignments" : "makeups")}><span className={`notice-icon ${notice.tone}`}>{notice.label === "상담" ? "☏" : notice.label === "과제" ? "✎" : "↻"}</span><span><b>{text}</b><small>{notice.label} 관리에서 확인하기</small></span><strong>{count}</strong><i>›</i></button>; })}</div></section>
      <section className="panel weekly-panel"><PanelHeader title="이번 주 출결" action="출결 관리" onClick={() => onNavigate("attendance")} /><div className="week-bars">{(live?.weekAttendance ?? []).map((day) => { const value = day.checked ? Math.round((day.present / day.checked) * 100) : 0; return <div key={day.weekday}><span><b>{["월","화","수","목","금"][day.weekday - 1]}</b><small>{day.checked ? `${value}%` : "–"}</small></span><i><em style={{width:`${value}%`}} /></i></div>; })}</div><div className="legend"><span><i className="dot wine" /> 출석 {weekTotals.present}</span><span><i className="dot amber" /> 지각 {weekTotals.late}</span><span><i className="dot gray" /> 결석 {weekTotals.absent}</span></div></section>
      <section className="panel activity-panel"><PanelHeader title="오늘 운영 집계" /><div className="activity-list"><Activity icon="✓" tone="green" title={`출결 입력 ${attendance?.checked ?? 0}건`} meta={`출석 ${attendance?.present ?? 0} · 지각 ${attendance?.late ?? 0} · 결석 ${attendance?.absent ?? 0}`}/><Activity icon="✎" tone="wine" title={`확인할 과제 ${assignmentCount?.total ?? 0}건`} meta={`미제출 ${assignmentCount?.unsubmitted ?? 0} · 첨삭 대기 ${assignmentCount?.reviewPending ?? 0}`}/><Activity icon="☏" tone="blue" title={`상담 점검 학생 ${consultationCount?.overdue ?? 0}명`} meta={`예정 상담 ${consultationCount?.upcoming ?? 0}건`}/><Activity icon="↻" tone="amber" title={`보강 필요 ${attendance?.makeup ?? 0}건`} meta="실시간 출결 기록 기준"/></div></section>
    </div>
  </>;
}

function Students({ rows,timetables, total, filteredTotal, statusFilter, loading, error, query, setQuery, onRegister, onOpen }: { rows: StudentRow[];timetables:Record<string,WeeklyTimetableRow[]>; total: number; filteredTotal:number; statusFilter:StudentStatusFilter; loading: boolean; error: string; query: string; setQuery: (value: string) => void; onRegister: () => void; onOpen: (student: StudentRow) => void }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">학생 통합 관리</p><h1>학생</h1><p>학생별 월–일 수강 시간표가 등록 클래스와 자동 연동됩니다.</p></div><button className="primary" onClick={onRegister}>＋ 학생 등록</button></div><section className="panel table-panel"><div className="table-tools"><div className="search-wrap inner"><span>⌕</span><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="이름, 학교, 과목 검색" /></div><span>{statusFilter==="all"?`전체 ${total}명`:`검색 결과 ${filteredTotal}명`}</span></div><div className="student-table"><div className="table-head"><span>학생</span><span>학교·학년</span><span>수강 과목</span><span>출석률</span><span>상태</span></div>{loading ? <StudentTableMessage>학생 데이터를 불러오는 중이에요…</StudentTableMessage> : error ? <StudentTableMessage error>{error}</StudentTableMessage> : rows.length === 0 ? <StudentTableMessage>{query||statusFilter!=="all" ? "선택한 조건의 학생이 없습니다." : "아직 등록된 학생이 없습니다."}</StudentTableMessage> : rows.map((student) => { const subjects = getStudentSubjects(student); const normalizedStatus=normalizeStudentStatus(student.status); return <article className="student-timetable-entry" key={student.id}><button className="table-row" onClick={() => onOpen(student)}><span className="student-name"><i>{student.name.slice(0,1)}</i><b>{student.name}</b></span><span>{[student.school, student.grade].filter(Boolean).join(" · ") || "-"}</span><span className="subject-tags">{subjects.length ? subjects.map(subject => <em key={subject}>{subject}</em>) : <em>미배정</em>}</span><strong>-</strong><span><i className={`status ${normalizedStatus==="active"?"active":normalizedStatus==="paused"?"warning":"completed"}`}>{studentStatusLabel(student.status)}</i></span></button><WeeklyTimetable compact rows={timetables[student.id]??[]}/></article>; })}</div></section></>;
}

function StudentRegistrationModal({ classes,schools,onAddSchool,onDeleteSchool,onReorderSchools,onClose, onSubmit }: { classes:AcademyClass[];schools:SchoolOption[];onAddSchool:(name:string)=>Promise<string>;onDeleteSchool:(id:string)=>Promise<void>;onReorderSchools:(schools:SchoolOption[])=>Promise<void>;onClose: () => void; onSubmit: (values: StudentFormValues) => Promise<void> }) {
  const [values, setValues] = useState<StudentFormValues>({ name: "", school: "", grade: "", phone: "", guardianName: "", guardianPhone: "", status: "active", internalNote: "",classIds:[] });
  const [selectedSubjects,setSelectedSubjects]=useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [schoolManagerOpen,setSchoolManagerOpen]=useState(false);
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
  const addSchool=async()=>{const name=window.prompt("추가할 학교 이름을 입력해 주세요.");if(!name?.trim())return;try{const saved=await onAddSchool(name);update("school",saved);}catch(nextError){setError(`학교를 추가하지 못했습니다. ${nextError instanceof Error?nextError.message:"다시 시도해 주세요."}`);}};
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="student-modal" role="dialog" aria-modal="true" aria-labelledby="student-registration-title"><header><div><p className="eyebrow">SUPABASE 학생 관리</p><h2 id="student-registration-title">학생 등록</h2><span>수강 과목을 먼저 고른 뒤 학생 학년에 맞는 클래스를 선택하세요.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><form onSubmit={submit}><div className="form-grid"><label>학생 이름 <b>*</b><input autoFocus required value={values.name} onChange={(event) => update("name", event.target.value)} placeholder="예: 김민준" /></label><label>학교<div className="school-select-row"><select value={values.school} onChange={(event)=>update("school",event.target.value)}><option value="">학교 선택</option>{schools.map((school)=><option value={school.name} key={school.id}>{school.name}</option>)}</select><button type="button" onClick={()=>void addSchool()}>＋ 학교 추가</button><button type="button" onClick={()=>setSchoolManagerOpen(true)}>학교 관리</button></div></label><label>학년<select value={values.grade} onChange={(event)=>update("grade",event.target.value)}><option value="">학년 선택</option>{studentGrades.map((grade)=><option value={grade} key={grade}>{grade}</option>)}</select></label><label>학생 연락처<input type="tel" inputMode="numeric" maxLength={13} value={values.phone} onChange={(event) => update("phone", formatPhoneNumber(event.target.value))} placeholder="숫자만 입력" /></label><label>학부모 성함<input value={values.guardianName} onChange={(event) => update("guardianName", event.target.value)} placeholder="예: 김보호" /></label><label>학부모 연락처<input type="tel" inputMode="numeric" maxLength={13} value={values.guardianPhone} onChange={(event) => update("guardianPhone", formatPhoneNumber(event.target.value))} placeholder="숫자만 입력" /></label><label>재원 상태<select value={values.status} onChange={(event) => update("status", event.target.value)}><option value="active">재원</option><option value="paused">휴원</option><option value="completed">퇴원</option></select></label><fieldset className="registration-subject-picker full"><legend><b>1</b> 수강 과목 <small>여러 개 선택 가능</small></legend><div>{subjects.map((subject)=><button type="button" role="checkbox" aria-checked={selectedSubjects.includes(subject)} className={selectedSubjects.includes(subject)?"selected":""} key={subject} onClick={()=>toggleSubject(subject)}><span>{subject}</span><small>{classes.filter((item)=>item.subject===subject).length}개 클래스</small></button>)}{!subjects.length&&<p>등록된 과목과 클래스가 없습니다. 클래스 관리에서 먼저 만들어 주세요.</p>}</div></fieldset><fieldset className="registration-class-picker full"><legend><b>2</b> 학년에 맞는 클래스 <small>{values.grade?`${values.grade} 기준`:"학년을 선택해 주세요"}</small></legend><div>{visibleClasses.map((item)=><button type="button" role="checkbox" aria-checked={values.classIds.includes(item.id)} className={values.classIds.includes(item.id)?"selected":""} key={item.id} onClick={()=>toggleClass(item.id)}><i style={{background:item.color}}/><span><b>{item.name}</b><em>{item.subject}{gradeCode(item.name)?` · ${gradeCode(item.name)}`:" · 공통"}</em></span></button>)}{selectedSubjects.length===0&&<p>먼저 위에서 수강 과목을 선택해 주세요.</p>}{selectedSubjects.length>0&&!visibleClasses.length&&<p>{values.grade?`${values.grade}에 맞는 운영 중 클래스가 없습니다. 클래스 이름에 학년을 확인해 주세요.`:"학년을 선택하면 맞는 클래스만 표시됩니다."}</p>}</div></fieldset><label className="full">내부 메모<textarea value={values.internalNote} onChange={(event) => update("internalNote", event.target.value)} placeholder="관리자와 교사만 확인할 메모" rows={3} /></label></div>{error && <p className="form-error" role="alert">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={submitting}>{submitting ? "저장 중…" : "학생 등록"}</button></footer></form>{schoolManagerOpen&&<SchoolManager schools={schools} onDelete={onDeleteSchool} onReorder={onReorderSchools} onClose={()=>setSchoolManagerOpen(false)}/>}</section></div>;
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

function LoginScreen({ onSubmit, error }: { onSubmit: (email: string, password: string) => Promise<void>; error: string }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [rememberEmail, setRememberEmail] = useState(false);
  const [submitting, setSubmitting] = useState(false);
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
  return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>한살매 입시전문학원</h1><p className="auth-copy">등록된 교사·학생·학부모 계정으로 로그인하세요.</p><form onSubmit={submit}><label>이메일<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required placeholder="name@example.com" /></label><label>비밀번호<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" required placeholder="비밀번호" /></label><label className="remember-email"><input type="checkbox" checked={rememberEmail} onChange={(event) => setRememberEmail(event.target.checked)} /><span>아이디 저장</span></label>{error && <p className="auth-error" role="alert">{error}</p>}<button className="primary" disabled={submitting}>{submitting ? "로그인 중…" : "로그인"}</button></form><small>계정과 역할 변경은 학원 관리자에게 문의해 주세요.</small></section></main>;
}

function LoadingScreen() { return <main className="auth-shell"><section className="auth-card loading"><img src="/hansalmae-logo.png" alt="" /><p>로그인 정보를 확인하고 있어요…</p></section></main>; }
function ConfigurationScreen() { return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>연결 설정이 필요합니다</h1><p className="auth-copy">Supabase 공개 URL과 anon key를 환경 변수에 등록해 주세요.</p></section></main>; }
function AccessPendingScreen({ email, error, onSignOut }: { email: string; error: string; onSignOut: () => void }) { return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>접근 권한 확인</h1><p className="auth-copy">{error || `${email} 계정에 아직 역할이 지정되지 않았습니다.`}</p><button className="secondary-button" onClick={onSignOut}>다른 계정으로 로그인</button></section></main>; }

function Stat({ label, value, unit, detail, icon, tone }: { label: string; value: string; unit: string; detail: string; icon: string; tone: string }) { return <article className="stat-card"><div className={`stat-icon ${tone}`}>{icon}</div><div><span>{label}</span><p><strong>{value}</strong> {unit}</p><small>{detail}</small></div></article>; }
function PanelHeader({ title, action, onClick }: { title: string; action?: string; onClick?: () => void }) { return <div className="panel-header"><h2>{title}</h2>{action && <button onClick={onClick}>{action} <span>›</span></button>}</div>; }
function Activity({ icon, tone, title, meta }: { icon: string; tone: string; title: string; meta: string }) { return <div className="activity"><span className={`notice-icon ${tone}`}>{icon}</span><div><b>{title}</b><small>{meta}</small></div></div>; }
