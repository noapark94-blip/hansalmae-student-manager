"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Dashboard = { counts: Record<string, number>; tableCounts?: Record<string, number>; recentLogs: { id: string; action: string; section: string; recordCount: number; createdAt: string; requestedBy: string }[] };
type Backup = { metadata: { app: string; version: number; exportedAt: string; section: string; recordCount: number; tableCount?: number }; data: Record<string, unknown[]> };

const sections = [
  { id: "students", icon: "학생", title: "학생·보호자", desc: "학생 기본 정보, 보호자 연결, 학교 및 재원 이력", tables: 6 },
  { id: "classes", icon: "수업", title: "클래스·계정", desc: "클래스, 시간표, 수강 배정 및 계정 설정", tables: 13 },
  { id: "learning", icon: "기록", title: "학습·상담 기록", desc: "출결, 보강, 과제, 시험, 특강 및 상담", tables: 17 },
  { id: "operations", icon: "운영", title: "운영 시간표", desc: "첨삭 배정·보고서, 차량 운행 및 예외 일정", tables: 12 },
  { id: "billing", icon: "수납", title: "수납", desc: "청구, 납부, 할인·추가금 및 수강료 정책", tables: 6 },
  { id: "communications", icon: "소식", title: "공지·문자", desc: "공지와 읽음 상태, 문자 발송 및 가족 알림", tables: 4 },
] as const;

export function BackupBoard({ supabase }: { supabase: SupabaseClient }) {
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [validation, setValidation] = useState<{ count: number; tables: number; name: string; version: number } | null>(null);
  const input = useRef<HTMLInputElement>(null);
  const load = useCallback(async () => { const { data, error: e } = await supabase.rpc("admin_backup_dashboard"); if (e) setError("백업 현황을 불러오지 못했습니다."); else setDashboard(data as Dashboard); }, [supabase]);
  useEffect(() => {
    // 데이터 조회 결과는 비동기로 반영됩니다.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const exportData = async (section: string, format: "json" | "csv") => {
    setBusy(`${section}-${format}`); setError("");
    const { data, error: e } = await supabase.rpc("admin_export_backup", { p_section: section, p_format: format });
    if (e) setError(e.message);
    else {
      const backup = data as Backup;
      const stamp = new Date().toISOString().slice(0, 19).replaceAll(":", "");
      download(`한살매_${section}_${stamp}.${format}`, format === "json" ? JSON.stringify(backup, null, 2) : toCsv(backup.data), format === "json" ? "application/json" : "text/csv;charset=utf-8");
      await load();
    }
    setBusy("");
  };
  const validate = async (file: File) => {
    setError(""); setValidation(null);
    try {
      const parsed = JSON.parse(await file.text()) as Backup;
      if (parsed?.metadata?.app !== "hansalmae-student-manager" || ![1, 2].includes(parsed.metadata.version) || !parsed.data || typeof parsed.data !== "object") throw new Error();
      const rows = Object.values(parsed.data); if (rows.some((item) => !Array.isArray(item))) throw new Error();
      const count = rows.reduce((sum, item) => sum + item.length, 0);
      setValidation({ count, tables: rows.length, name: file.name, version: parsed.metadata.version });
      await supabase.rpc("admin_log_restore_validation", { p_record_count: count }); await load();
    } catch { setError("한살매에서 생성한 올바른 JSON 내보내기 파일이 아닙니다."); }
  };
  const totalRecords = sections.reduce((sum, section) => sum + (dashboard?.counts?.[section.id] ?? 0), 0);
  const totalTables = sections.reduce((sum, section) => sum + (dashboard?.tableCounts?.[section.id] ?? section.tables), 0);

  return <div className="backup-page">
    <section className="backup-hero"><div><p className="eyebrow">관리자 전용 · 데이터 보호</p><h1>데이터 백업</h1><p>현재 운영 중인 데이터를 영역별로 내보내고, 복구용 SQL 백업 방법까지 한곳에서 확인합니다.</p><div className="backup-summary"><span><b>{dashboard ? totalRecords.toLocaleString("ko-KR") : "–"}</b>전체 레코드</span><span><b>{totalTables}</b>포함 테이블</span><span><b>{sections.length}</b>데이터 영역</span></div></div><button className="backup-main-action" disabled={!!busy} onClick={() => void exportData("all", "json")}><span>{busy === "all-json" ? "생성 중…" : "전체 운영 데이터"}</span><small>JSON으로 내보내기</small></button></section>
    {error && <p className="backup-error">{error}</p>}
    <div className="backup-section-heading"><div><h2>영역별 내보내기</h2><p>필요한 데이터만 JSON 또는 CSV 파일로 보관할 수 있습니다.</p></div><span>현재 기능 기준으로 갱신됨</span></div>
    <div className="backup-grid">{sections.map((section) => <article className="backup-card" key={section.id}><header><i>{section.icon}</i><span>{dashboard?.tableCounts?.[section.id] ?? section.tables}개 테이블</span></header><h3>{section.title}</h3><strong>{dashboard?.counts?.[section.id]?.toLocaleString("ko-KR") ?? "–"}<small>건</small></strong><p>{section.desc}</p><footer><button disabled={!!busy} onClick={() => void exportData(section.id, "json")}>{busy === `${section.id}-json` ? "생성 중…" : "JSON"}</button><button disabled={!!busy} onClick={() => void exportData(section.id, "csv")}>{busy === `${section.id}-csv` ? "생성 중…" : "CSV"}</button></footer></article>)}</div>
    <div className="backup-tools">
      <section className="backup-tool"><div className="backup-tool-icon">검증</div><div><h2>내보내기 파일 확인</h2><p>한살매 JSON 파일의 형식과 테이블·레코드 수를 확인합니다. 데이터는 변경되지 않습니다.</p></div><input ref={input} hidden type="file" accept="application/json,.json" onChange={(event) => { const file = event.target.files?.[0]; if (file) void validate(file); event.target.value = ""; }} /><button onClick={() => input.current?.click()}>JSON 파일 선택</button>{validation && <div className="backup-valid"><b>파일 확인 완료</b><span>{validation.name}</span><small>버전 {validation.version} · {validation.tables}개 테이블 · {validation.count.toLocaleString("ko-KR")}건</small></div>}</section>
      <section className="backup-tool backup-sql"><div className="backup-tool-icon">SQL</div><div><h2>복구용 SQL 백업</h2><p>DB 구조, 실제 데이터, 역할을 각각 저장합니다. Supabase 관리 영역인 Auth·Storage는 제외됩니다.</p></div><code>.\scripts\backup-supabase.ps1</code><small>Windows PowerShell · 프로젝트 폴더에서 실행</small></section>
    </div>
    <section className="backup-history"><header><div><h2>최근 작업 기록</h2><p>파일 내보내기와 검증 이력을 최신순으로 표시합니다.</p></div><span>최근 15건</span></header>{dashboard?.recentLogs?.length ? <div className="backup-history-list">{dashboard.recentLogs.map((log) => <article key={log.id}><i>{log.action === "validate_restore" ? "검증" : log.action === "export_csv" ? "CSV" : "JSON"}</i><span><b>{actionLabel(log.action)}</b><small>{log.requestedBy} · {sectionLabel(log.section)}</small></span><em>{log.recordCount.toLocaleString("ko-KR")}건</em><time>{new Date(log.createdAt).toLocaleString("ko-KR")}</time></article>)}</div> : <p className="backup-empty">아직 내보내기 기록이 없습니다.</p>}</section>
    <p className="backup-footnote">운영 데이터 내보내기는 일상적인 확인·보관용이며, 전체 복구가 필요한 경우에는 SQL 백업 파일을 사용하세요.</p>
  </div>;
}

function download(name: string, text: string, type: string) { const url = URL.createObjectURL(new Blob([type.startsWith("text/csv") ? "\ufeff" + text : text], { type })); const anchor = document.createElement("a"); anchor.href = url; anchor.download = name; anchor.click(); URL.revokeObjectURL(url); }
function toCsv(data: Record<string, unknown[]>) { const rows: Array<[string, string]> = [["table", "record_json"]]; Object.entries(data).forEach(([table, items]) => items.forEach((item) => rows.push([table, JSON.stringify(item) ?? ""]))); return rows.map((row) => row.map((value) => `"${value.replaceAll('"', '""')}"`).join(",")).join("\n"); }
function actionLabel(value: string) { return value === "export_json" ? "JSON 데이터 내보내기" : value === "export_csv" ? "CSV 데이터 내보내기" : "JSON 파일 확인"; }
function sectionLabel(value: string) { return value === "all" ? "전체 영역" : sections.find((section) => section.id === value)?.title ?? value; }
