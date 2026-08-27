"use client";

import { useCallback, useEffect, useState } from "react";
import { createPortal } from "react-dom";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";

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
};

export function NotificationCenter({ supabase, onOpenFamilyReport }: { supabase: SupabaseClient; onOpenFamilyReport?: () => void }) {
  const [open, setOpen] = useState(false);
  const [mode, setMode] = useState<"staff" | "family" | "general" | null>(null);
  const [inbox, setInbox] = useState<Inbox>({ unreadCount: 0, items: [] });
  const [selected, setSelected] = useState<InboxItem | null>(null);
  const [thread, setThread] = useState<ThreadComment[]>([]);
  const [reply, setReply] = useState("");
  const [saving, setSaving] = useState(false);
  const load = useCallback(async () => {
    const [staff, family, general] = await Promise.all([
      supabase.rpc("staff_report_comment_inbox"),
      supabase.rpc("family_report_reply_inbox"),
      supabase.rpc("family_notification_center"),
    ]);
    if (!staff.error) {
      setMode("staff");
      setInbox(staff.data as Inbox);
      return;
    }
    if (
      !family.error &&
      Number((family.data as Inbox)?.items?.length ?? 0) > 0
    ) {
      setMode("family");
      setInbox(family.data as Inbox);
      return;
    }
    if (!general.error) {
      setMode("general");
      setInbox(general.data as Inbox);
      return;
    }
    setMode(null);
    setInbox({ unreadCount: 0, items: [] });
  }, [supabase]);
  useEffect(() => {
    void Promise.resolve().then(load);
  }, [load]);
  useEffect(()=>{if(!open&&!selected)return;const previous=document.body.style.overflow;document.body.style.overflow="hidden";return()=>{document.body.style.overflow=previous}},[open,selected]);
  async function openItem(item: InboxItem) {
    if (mode !== "staff") {
      const lessonId=item.lessonId??(item.sourceType==="learning_report"?item.sourceId:undefined);
      if(!lessonId)return;
      if(mode==="general")void supabase.rpc("mark_family_notifications_read",{p_notification_id:item.id});
      setOpen(false);
      onOpenFamilyReport?.();
      sessionStorage.setItem("hansalmae:family-report-target",JSON.stringify({lessonId,studentId:item.studentId}));
      window.setTimeout(()=>window.dispatchEvent(new CustomEvent("hansalmae:open-family-report",{detail:{lessonId,studentId:item.studentId}})),50);
      return;
    }
    if (!item.studentId || !item.lessonId) return;
    setSelected(item);
    setReply("");
    const { data } = await supabase.rpc("staff_report_comments", {
      p_student_id: item.studentId,
      p_lesson_id: item.lessonId,
    });
    setThread((data ?? []) as ThreadComment[]);
    void load();
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
              <button type="button" onClick={() => setOpen(false)}>
                ×
              </button>
            </header>
            <div className="notification-toolbar">
              <span>
                {mode === "staff"
                  ? `미확인 댓글 ${inbox.unreadCount}건`
                  : `새 알림 ${inbox.unreadCount}건`}
              </span>
              <button type="button" onClick={() => void load()}>
                새로고침
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
                    <i>{mode === "staff" ? "댓" : "알"}</i>
                    <span>
                      <b>
                        {mode === "staff"
                          ? `${item.studentName} · ${item.subject ?? "수업"}`
                          : (item.title ?? item.studentName)}
                      </b>
                      <small>
                        {[
                          item.className,
                          item.authorName,
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
              <span />
            </header>
            <div className="comment-thread-list">
              {thread
                .filter((item) => !item.parentId)
                .map((root) => (
                  <article key={root.id}>
                    <div>
                      <b>{root.authorName} 학부모님</b>
                      <time>{formatTime(root.createdAt)}</time>
                    </div>
                    <p>{root.body}</p>
                    {thread
                      .filter((item) => item.parentId === root.id)
                      .map((item) => (
                        <section key={item.id}>
                          <b>{item.authorName} 선생님</b>
                          <p>{item.body}</p>
                          <time>{formatTime(item.createdAt)}</time>
                        </section>
                      ))}
                  </article>
                ))}
            </div>
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
