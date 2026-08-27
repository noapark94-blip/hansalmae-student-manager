"use client";

import { useCallback, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

export type ReactionKind = "heart" | "confirm" | "done" | "thanks";
type ReactionCount = { type: ReactionKind; count: number; selected: boolean };
type ReactionRow = { commentId: string; reactions: ReactionCount[] };
export type ReactionMap = Record<string, ReactionCount[]>;

const choices: { type: ReactionKind; icon: string; label: string }[] = [
  { type: "heart", icon: "♥", label: "공감" },
  { type: "confirm", icon: "✓", label: "확인" },
  { type: "done", icon: "●", label: "처리" },
  { type: "thanks", icon: "✦", label: "감사" },
];

export function useReportCommentReactions(supabase: SupabaseClient) {
  const [reactions, setReactions] = useState<ReactionMap>({});
  const [reacting, setReacting] = useState<string | null>(null);
  const load = useCallback(async (ids: string[]) => {
    if (!ids.length) { setReactions({}); return; }
    const { data, error } = await supabase.rpc("report_comment_reactions", { p_comment_ids: ids });
    if (error) return;
    const rows = (data ?? []) as ReactionRow[];
    setReactions((current) => ({ ...current, ...Object.fromEntries(rows.map((row) => [row.commentId, row.reactions])) }));
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
  if (disabled) return null;
  return <div className={`comment-reactions${open ? " open" : ""}`}>
    <div className="comment-reaction-totals">
      {items.filter((item) => item.count > 0).map((item) => {
        const choice = choices.find((choiceItem) => choiceItem.type === item.type)!;
        return <button type="button" key={item.type} className={item.selected ? "selected" : ""} title={choice.label} disabled={reacting} onClick={() => onToggle(commentId, item.type)}><i>{choice.icon}</i><span>{item.count}</span></button>;
      })}
      <button type="button" className="comment-reaction-trigger" aria-expanded={open} onClick={() => setOpen((value) => !value)}><i>＋</i><span>반응</span></button>
    </div>
    {open && <div className="comment-reaction-picker" role="menu" aria-label="댓글 반응 선택">
      {choices.map((choice) => <button type="button" role="menuitem" key={choice.type} disabled={reacting} onClick={() => { onToggle(commentId, choice.type); setOpen(false); }}><i className={choice.type}>{choice.icon}</i><span>{choice.label}</span></button>)}
    </div>}
  </div>;
}
