"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";
import { appConfirm } from "./app-dialog";
import { familyTeacherName } from "./family-teacher-name";
import {
  CommentReactionBar,
  useReportCommentReactions,
} from "./report-comment-reactions";

type InboxItem = {
  id: string;
  lessonId?: string;
  studentId?: string;
  studentName: string;
  className?: string;
  subject?: string;
  title?: string;
  sourceType?: string;
  sourceId?: string;
  body: string;
  authorName?: string;
  readAt: string | null;
  createdAt: string;
};
type Inbox = { unreadCount: number; items: InboxItem[] };
type ThreadComment = {
  id: string;
  parentId: string | null;
  body: string;
  authorName: string;
  authorRole: string;
  createdAt: string;
  canDelete: boolean;
  isDeleted: boolean;
};
export type StaffLessonTarget={classId:string;date:string;requestId:number};

export function NotificationCenter({ supabase, onOpenFamilyReport, onOpenStaffLesson }: { supabase: SupabaseClient; onOpenFamilyReport?: () => void; onOpenStaffLesson?: (target:StaffLessonTarget) => void }) {
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"staff" | "family" | "general" | null>(null);
  const [inbox, setInbox] = useState<Inbox>({ unreadCount: 0, items: [] });
  const [selected, setSelected] = useState<InboxItem | null>(null);
  const [thread, setThread] = useState<ThreadComment[]>([]);
  const [reply, setReply] = useState("");
  const [saving, setSaving] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [refreshResult, setRefreshResult] = useState<"idle" | "done" | "error">("idle");
  const refreshResultTimer = useRef<number | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [threadError, setThreadError] = useState("");
  const { reactions, reacting, load: loadReactions, toggle } =
    useReportCommentReactions(supabase);
  const load = useCallback(async () => {
    const [staff, family, general] = await Promise.all([
      supabase.rpc("staff_report_comment_inbox"),
      supabase.rpc("family_report_reply_inbox"),
      supabase.rpc("family_notification_center"),
    ]);
    if (!staff.error) {
      setMode("staff");
      setInbox((current) => sameData(current, staff.data as Inbox) ? current : staff.data as Inbox);
      return true;
    }
    if (
      !family.error &&
      Number((family.data as Inbox)?.items?.length ?? 0) > 0
    ) {
      setMode("family");
      setInbox((current) => sameData(current, family.data as Inbox) ? current : family.data as Inbox);
      return true;
    }
    if (!general.error) {
      setMode("general");
      setInbox((current) => sameData(current, general.data as Inbox) ? current : general.data as Inbox);
      return true;
    }
    setMode(null);
    setInbox({ unreadCount: 0, items: [] });
    return false;
  }, [supabase]);
  useEffect(() => {
    void Promise.resolve().then(load);
  }, [load]);
  useEffect(() => () => {
    if (refreshResultTimer.current) window.clearTimeout(refreshResultTimer.current);
  }, []);
  useEffect(() => {
    const refresh = () => {
      if (document.visibilityState === "visible") void load();
    };
    const intervalId = window.setInterval(refresh, 5000);
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.clearInterval(intervalId);
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [load]);
  useEffect(() => {
    if (!selected?.studentId || !selected.lessonId) return;
    const refreshThread = async () => {
      if (document.visibilityState !== "visible") return;
      const { data } = await supabase.rpc("staff_report_comments", {
        p_student_id: selected.studentId,
        p_lesson_id: selected.lessonId,
      });
      if (data) {
        const nextThread = data as ThreadComment[];
        setThread((current) => sameData(current, nextThread) ? current : nextThread);
        await loadReactions(
          nextThread.filter((item) => !item.isDeleted).map((item) => item.id),
        );
      }
    };
    const intervalId = window.setInterval(() => void refreshThread(), 5000);
    return () => window.clearInterval(intervalId);
  }, [loadReactions, selected?.lessonId, selected?.studentId, supabase]);
  useEffect(()=>{if(!open&&!selected)return;const previous=document.body.style.overflow;document.body.style.overflow="hidden";return()=>{document.body.style.overflow=previous}},[open,selected]);
  function markItemRead(item:InboxItem){
    if(item.readAt)return;
    const readAt=new Date().toISOString();
    setInbox(current=>({
      unreadCount:Math.max(0,current.unreadCount-1),
      items:current.items.map(currentItem=>currentItem.id===item.id?{...currentItem,readAt}:currentItem),
    }));
  }
  async function openItem(item: InboxItem) {
    markItemRead(item);
    if (mode !== "staff") {
      const lessonId=item.lessonId??(item.sourceType==="learning_report"?item.sourceId:undefined);
      if(!lessonId)return;
      if(mode==="general")void supabase.rpc("mark_family_notifications_read",{p_notification_id:item.id});
      setOpen(false);
      sessionStorage.setItem("hansalmae:family-report-target",JSON.stringify({lessonId,studentId:item.studentId}));
      onOpenFamilyReport?.();
      window.setTimeout(()=>window.dispatchEvent(new CustomEvent("hansalmae:open-family-report",{detail:{lessonId,studentId:item.studentId}})),50);
      return;
    }
    if (!item.studentId || !item.lessonId) return;
    setOpen(false);
    setSelected(item);
    setReply("");
    setThreadError("");
    const { data } = await supabase.rpc("staff_report_comments", {
      p_student_id: item.studentId,
      p_lesson_id: item.lessonId,
    });
    const nextThread = (data ?? []) as ThreadComment[];
    setThread(nextThread);
    await loadReactions(
      nextThread.filter((comment) => !comment.isDeleted).map((comment) => comment.id),
    );
    void load();
  }
  async function removeComment(item:ThreadComment) {
    if (!selected || deleting || !item.canDelete) return;
    const confirmed=await appConfirm({eyebrow:"댓글 삭제",title:item.parentId?"작성한 답변을 삭제할까요?":"이 댓글을 삭제할까요?",notice:item.parentId?"학부모 댓글도 이미 삭제된 상태라면 빈 대화 전체가 정리됩니다.":"선생님이 남긴 답변은 그대로 유지됩니다.",confirmLabel:"삭제",tone:"danger"});
    if(!confirmed)return;
    setDeleting(item.id);setThreadError("");
    const{error}=await supabase.rpc("delete_report_comment",{p_comment_id:item.id});
    if(error)setThreadError("댓글을 삭제하지 못했습니다.");else await openItem(selected);
    setDeleting(null);
  }
  async function submit() {
    if (!selected || !reply.trim() || saving) return;
    setSaving(true);
    const { error } = await supabase.rpc("staff_reply_report_comment", {
      p_comment_id: selected.id,
      p_body: reply.trim(),
    });
    if (!error) {
      setReply("");
      await openItem(selected);
    }
    setSaving(false);
  }
  async function openStaffLesson() {
    if(!selected?.lessonId||!selected.studentId)return;
    const{data,error}=await supabase.rpc("staff_report_comment_lesson_target",{p_student_id:selected.studentId,p_lesson_id:selected.lessonId});
    if(error||!data)return;
    const target={classId:String((data as {classId:string}).classId),date:String((data as {lessonDate:string}).lessonDate),requestId:Date.now()};
    setSelected(null);
    onOpenStaffLesson?.(target);
  }
  async function refreshInbox() {
    if (refreshing) return;
    setRefreshing(true);
    setRefreshResult("idle");
    if (refreshResultTimer.current) window.clearTimeout(refreshResultTimer.current);
    const startedAt = Date.now();
    const succeeded = await load();
    const remaining = Math.max(0, 450 - (Date.now() - startedAt));
    if (remaining) await new Promise((resolve) => window.setTimeout(resolve, remaining));
    setRefreshing(false);
    setRefreshResult(succeeded ? "done" : "error");
    refreshResultTimer.current = window.setTimeout(() => setRefreshResult("idle"), 1600);
  }
  return (
    <>
      <button
        type="button"
        className="icon-button notification-button"
        aria-label={`알림${inbox.unreadCount ? ` ${inbox.unreadCount}개` : ""}`}
        onClick={() => setOpen(true)}
      >
        <HansalmaeIcon name="notice" size={21} />
        {inbox.unreadCount > 0 && (
          <i>{inbox.unreadCount > 99 ? "99+" : inbox.unreadCount}</i>
        )}
      </button>
      {typeof document!=="undefined"&&open&&createPortal(
        <div
          className="notification-backdrop"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setOpen(false);
          }}
        >
          <section className="notification-drawer">
            <header>
              <div>
                <small>
                  {mode === "staff" ? "학부모 소통" : "한살매 수업노트"}
                </small>
                <h2>{mode === "staff" ? "댓글 알림" : "알림"}</h2>
              </div>
              <button type="button" aria-label="알림 닫기" onClick={() => setOpen(false)}>
                ×
              </button>
            </header>
            <div className="notification-toolbar">
              <span>
                {mode === "staff"
                  ? `미확인 댓글 ${inbox.unreadCount}건`
                  : `새 알림 ${inbox.unreadCount}건`}
              </span>
              <button
                type="button"
                className={`notification-refresh ${refreshResult}`}
                onClick={() => void refreshInbox()}
                disabled={refreshing}
                aria-live="polite"
              >
                <span aria-hidden="true">{refreshResult === "done" ? "✓" : "↻"}</span>
                {refreshing
                  ? "확인 중"
                  : refreshResult === "done"
                    ? "업데이트 완료"
                    : refreshResult === "error"
                      ? "다시 시도"
                      : "새로고침"}
              </button>
            </div>
            <div className="notification-list">
              {!inbox.items.length ? (
                <p>
                  {mode === "staff"
                    ? "새로운 학부모 댓글이 없습니다."
                    : "새로운 알림이 없습니다."}
                </p>
              ) : (
                inbox.items.map((item) => (
                  <article
                    key={item.id}
                    className={!item.readAt ? "unread" : ""}
                    onClick={() => void openItem(item)}
                    role={mode === "staff"||item.lessonId||(item.sourceType==="learning_report"&&item.sourceId) ? "button" : undefined}
                  >
                    <i aria-hidden="true"><HansalmaeIcon name={mode === "general" ? "notice" : "chat"} size={18}/></i>
                    <span>
                      <b>
                        {mode === "staff"
                          ? `${item.studentName} · ${item.subject ?? "수업"}`
                          : (item.title ?? item.studentName)}
                      </b>
                      <small>
                        {[
                          item.className,
                          mode === "staff" ? item.authorName : familyTeacherName(item.authorName),
                          formatTime(item.createdAt),
                        ]
                          .filter(Boolean)
                          .join(" · ")}
                      </small>
                      <p>{item.body}</p>
                    </span>
                  </article>
                ))
              )}
            </div>
          </section>
        </div>,document.body
      )}
      {typeof document!=="undefined"&&selected&&createPortal(
        <div
          className="comment-thread-backdrop"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) setSelected(null);
          }}
        >
          <section className="comment-thread-dialog">
            <header>
              <button type="button" onClick={() => setSelected(null)}>
                ‹
              </button>
              <div>
                <small>
                  {selected.studentName} · {selected.subject}
                </small>
                <h2>리포트 댓글</h2>
              </div>
              <button type="button" className="comment-thread-lesson-button" onClick={()=>void openStaffLesson()}><HansalmaeIcon name="book" size={15}/><span>수업 기록</span></button>
            </header>
            <div className="comment-thread-list">
              {thread
                .filter((item) => !item.parentId)
                .map((root) => (
                  <article key={root.id}>
                    <div>
                      <b>{root.authorName} 학부모님</b>
                      <span><time>{formatTime(root.createdAt)}</time>{root.canDelete&&<button type="button" className="report-comment-delete" disabled={deleting===root.id} onClick={()=>void removeComment(root)}>{deleting===root.id?"삭제 중…":"삭제"}</button>}</span>
                    </div>
                    <p className={root.isDeleted?"deleted":""}>{root.body}</p>
                    <CommentReactionBar commentId={root.id} items={reactions[root.id]??[]} disabled={root.isDeleted} reacting={reacting===root.id} onToggle={(commentId,type)=>void toggle(commentId,type)}/>
                    {thread
                      .filter((item) => item.parentId === root.id)
                      .map((item) => (
                        <section key={item.id}>
                          <div className="comment-reply-meta"><b>{familyTeacherName(item.authorName)}</b><span><time>{formatTime(item.createdAt)}</time>{item.canDelete&&<button type="button" className="report-comment-delete" disabled={deleting===item.id} onClick={()=>void removeComment(item)}>{deleting===item.id?"삭제 중…":"삭제"}</button>}</span></div>
                          <p>{item.body}</p>
                          <CommentReactionBar commentId={item.id} items={reactions[item.id]??[]} disabled={item.isDeleted} reacting={reacting===item.id} onToggle={(commentId,type)=>void toggle(commentId,type)}/>
                        </section>
                      ))}
                  </article>
                ))}
            </div>
            {threadError&&<p className="comment-thread-error">{threadError}</p>}
            <footer>
              <textarea
                maxLength={500}
                rows={3}
                value={reply}
                onChange={(event) => setReply(event.target.value)}
                placeholder="학부모님께 답변을 입력하세요"
              />
              <div>
                <span>{reply.length}/500</span>
                <button
                  type="button"
                  disabled={!reply.trim() || saving}
                  onClick={() => void submit()}
                >
                  {saving ? "답변 중…" : "답변 등록"}
                </button>
              </div>
            </footer>
          </section>
        </div>,document.body
      )}
    </>
  );
}

function formatTime(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
}

function sameData(left: unknown, right: unknown) {
  return JSON.stringify(left) === JSON.stringify(right);
}
