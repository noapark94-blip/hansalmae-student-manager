"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

export type ReactionKind = "heart" | "confirm" | "done" | "thanks";
type ReactionCount = { type: ReactionKind; count: number; selected: boolean };
type ReactionRow = { commentId: string; reactions: ReactionCount[] };
export type ReactionMap = Record<string, ReactionCount[]>;

const choices: { type: ReactionKind; icon: string; label: string }[] = [
  { type: "heart", icon: "heart", label: "공감" },
  { type: "confirm", icon: "thumb", label: "좋아요" },
  { type: "done", icon: "check", label: "확인" },
];

function ReactionIcon({ kind }: { kind: ReactionKind }) {
  if (kind === "heart") return <svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#ff4b55" d="M24 42.2 7.1 25.7C-2.7 16.2 3.1 5 13.4 5c5 0 8.3 2.9 10.6 6.1C26.3 7.9 29.6 5 34.6 5 44.9 5 50.7 16.2 40.9 25.7L24 42.2Z"/></svg>;
  if (kind === "confirm") return <svg viewBox="0 0 48 48" aria-hidden="true"><path fill="#ffbf24" stroke="#eda600" strokeWidth="1.2" strokeLinejoin="round" d="M17.6 42H9.2V22.2h8.4V42Zm3.1-19.8c4.5-3.8 6.8-9.1 7.6-15.1.3-2.1 2-3.3 3.7-2.8 2.7.8 3.3 4.5 2.5 9.3l-.8 4.2h6.6c3.2 0 5.2 2.8 4.3 5.5l-4.5 14.9c-.7 2.3-2.8 3.8-5.2 3.8H20.7V22.2Z"/></svg>;
  return <svg viewBox="0 0 48 48" aria-hidden="true"><circle cx="24" cy="24" r="21" fill="#2f91eb"/><path fill="none" stroke="#fff" strokeWidth="5" strokeLinecap="round" strokeLinejoin="round" d="m13.5 24.5 7 7 14-16"/></svg>;
}

export function useReportCommentReactions(supabase: SupabaseClient) {
  const [reactions, setReactions] = useState<ReactionMap>({});
  const [reacting, setReacting] = useState<string | null>(null);
  const load = useCallback(async (ids: string[]) => {
    if (!ids.length) { setReactions({}); return; }
    const { data, error } = await supabase.rpc("report_comment_reactions", { p_comment_ids: ids });
    if (error) return;
    const rows = (data ?? []) as ReactionRow[];
    const next = Object.fromEntries(rows.map((row) => [row.commentId, row.reactions]));
    setReactions((current) => {
      const unchanged = Object.entries(next).every(
        ([id, value]) => JSON.stringify(current[id] ?? []) === JSON.stringify(value),
      );
      return unchanged ? current : { ...current, ...next };
    });
  }, [supabase]);
  const toggle = useCallback(async (commentId: string, type: ReactionKind) => {
    if (reacting) return;
    setReacting(commentId);
    const { error } = await supabase.rpc("toggle_report_comment_reaction", { p_comment_id: commentId, p_reaction: type });
    if (!error) await load([commentId]);
    setReacting(null);
  }, [load, reacting, supabase]);
  return { reactions, reacting, load, toggle };
}

export function CommentReactionBar({ commentId, items, disabled, reacting, onToggle }: { commentId: string; items: ReactionCount[]; disabled?: boolean; reacting: boolean; onToggle: (commentId: string, type: ReactionKind) => void }) {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const closeOutside = (event: PointerEvent) => {
      if (!containerRef.current?.contains(event.target as Node)) setOpen(false);
    };
    const closeWithEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("pointerdown", closeOutside);
    document.addEventListener("keydown", closeWithEscape);
    return () => {
      document.removeEventListener("pointerdown", closeOutside);
      document.removeEventListener("keydown", closeWithEscape);
    };
  }, [open]);

  if (disabled) return null;
  return <div ref={containerRef} className={`comment-reactions${open ? " open" : ""}`}>
    <div className="comment-reaction-totals">
      {items.filter((item) => item.count > 0).map((item) => {
        const choice = choices.find((choiceItem) => choiceItem.type === item.type);
        if (!choice) return null;
        return <button type="button" key={item.type} className={item.selected ? "selected" : ""} title={choice.label} disabled={reacting} onClick={() => onToggle(commentId, item.type)}><i><ReactionIcon kind={item.type}/></i><span>{item.count}</span></button>;
      })}
      <button type="button" className="comment-reaction-trigger" aria-expanded={open} onClick={() => setOpen((value) => !value)}><i>＋</i><span>반응</span></button>
    </div>
    {open && <div className="comment-reaction-picker" role="menu" aria-label="댓글 반응 선택">
      {choices.map((choice) => <button type="button" role="menuitem" aria-label={choice.label} title={choice.label} key={choice.type} disabled={reacting} onClick={() => { onToggle(commentId, choice.type); setOpen(false); }}><i className={choice.type}><ReactionIcon kind={choice.type}/></i></button>)}
    </div>}
  </div>;
}
