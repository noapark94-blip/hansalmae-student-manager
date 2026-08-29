"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type State = "checking" | "unsupported" | "off" | "on" | "saving" | "error";
type PromptMode = "intro" | "weekly" | "disabled";
const VAPID_PUBLIC_KEY = "BFtcz-HAAEgZVonjdQqk8hpZQwOMeQZObsTlL-jwoh_fdn9rWyt_GmaDOy77HEKQQ0qFazh-7PIGKtRB3BIfkuE";
const GUIDE_SEEN_KEY = "guardian_push_guide_seen";
const LAST_PROMPTED_KEY = "guardian_push_last_prompted_at";
const WAS_ENABLED_KEY = "guardian_push_was_enabled";
const DISABLED_PROMPT_SEEN_KEY = "guardian_push_disabled_prompt_seen";
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

function decodeKey(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0));
}

function supportsPush() {
  return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
}

async function subscribeToGuardianPush(supabase: SupabaseClient) {
  if (!supportsPush()) throw new Error("이 기기에서는 알림을 사용할 수 없습니다.");
  const registration = await navigator.serviceWorker.register("/push-service-worker.js");
  let subscription = await registration.pushManager.getSubscription();
  if (!subscription) {
    const permission = await Notification.requestPermission();
    if (permission !== "granted") throw new Error("기기 설정에서 알림을 허용해 주세요.");
    subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: decodeKey(VAPID_PUBLIC_KEY) });
  }
  const json = subscription.toJSON();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || !json.keys?.p256dh || !json.keys.auth) {
    await subscription.unsubscribe();
    throw new Error("구독 정보를 확인할 수 없습니다.");
  }
  const { error } = await supabase.from("push_subscriptions").upsert({
    profile_id: user.id, endpoint: subscription.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth, user_agent: navigator.userAgent,
  }, { onConflict: "profile_id,endpoint" });
  if (error) { await subscription.unsubscribe(); throw error; }
  return subscription;
}

async function rememberPromptChoice(supabase: SupabaseClient, data: Record<string, boolean | string>) {
  const { error } = await supabase.auth.updateUser({ data: {
    [GUIDE_SEEN_KEY]: true,
    [LAST_PROMPTED_KEY]: new Date().toISOString(),
    ...data,
  } });
  if (error) throw error;
}

export function GuardianPushPrompt({ supabase }: { supabase: SupabaseClient }) {
  const [mode, setMode] = useState<PromptMode | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(async ({ data }) => {
      const user = data.user;
      if (!active || !user || !supportsPush()) return;
      const registration = await navigator.serviceWorker.register("/push-service-worker.js");
      const subscription = await registration.pushManager.getSubscription();
      const enabled = Boolean(subscription && Notification.permission === "granted");
      const metadata = user.user_metadata ?? {};
      if (enabled) {
        if (metadata[WAS_ENABLED_KEY] !== true || metadata[DISABLED_PROMPT_SEEN_KEY] === true) {
          await supabase.auth.updateUser({ data: { [WAS_ENABLED_KEY]: true, [DISABLED_PROMPT_SEEN_KEY]: false } });
        }
        return;
      }
      if (subscription && Notification.permission !== "granted") {
        await supabase.from("push_subscriptions").delete().eq("profile_id", user.id).eq("endpoint", subscription.endpoint);
        try { await subscription.unsubscribe(); } catch { /* The OS may already have revoked it. */ }
      }
      if (!active) return;
      if (metadata[WAS_ENABLED_KEY] === true) {
        if (metadata[DISABLED_PROMPT_SEEN_KEY] !== true) setMode("disabled");
        return;
      }
      if (metadata[GUIDE_SEEN_KEY] !== true) { setMode("intro"); return; }
      const lastPrompted = Date.parse(String(metadata[LAST_PROMPTED_KEY] ?? ""));
      if (!Number.isFinite(lastPrompted) || Date.now() - lastPrompted >= WEEK_MS) setMode("weekly");
    }).catch(() => { /* Keep the app usable if push status cannot be checked. */ });
    return () => { active = false; };
  }, [supabase]);

  const close = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    try {
      await rememberPromptChoice(supabase, mode === "disabled" ? { [DISABLED_PROMPT_SEEN_KEY]: true } : {});
      setMode(null);
    }
    catch { setError("선택을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요."); }
    finally { setSaving(false); }
  }, [mode, saving, supabase]);

  const enable = useCallback(async () => {
    if (saving) return;
    setSaving(true); setError("");
    try {
      // iOS requires the permission request to remain in the direct button gesture.
      await subscribeToGuardianPush(supabase);
      await rememberPromptChoice(supabase, { [WAS_ENABLED_KEY]: true, [DISABLED_PROMPT_SEEN_KEY]: false });
      setMode(null);
    } catch (caught) {
      try { await rememberPromptChoice(supabase, mode === "disabled" ? { [DISABLED_PROMPT_SEEN_KEY]: true } : {}); } catch { /* Keep the actionable push error visible. */ }
      setError(caught instanceof Error ? caught.message : "알림을 켜지 못했습니다.");
    }
    finally { setSaving(false); }
  }, [mode, saving, supabase]);

  if (!mode) return null;
  return <div className="guardian-push-prompt-backdrop" role="presentation">
    <section className="guardian-push-prompt" role="dialog" aria-modal="true" aria-labelledby="guardian-push-title" aria-describedby="guardian-push-description">
      <div className="guardian-push-prompt-icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none">
          <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z" />
          <path d="M10 21h4" />
        </svg>
      </div>
      <p className="eyebrow">한살매 수업노트</p>
      <h2 id="guardian-push-title">{mode === "disabled" ? <>기기 알림이 꺼져 있어요<br />다시 연결해 드릴까요?</> : <>아이의 새 학습 기록을<br />바로 알려드릴게요</>}</h2>
      <p id="guardian-push-description">{mode === "disabled" ? <>알림 설정이 꺼진 것을 확인했어요.<br />다시 켜면 새 피드를 바로 받을 수 있어요.</> : <>수업·첨삭 리포트가 등록되면<br />이 기기에서 빠르게 확인할 수 있어요.</>}</p>
      {error ? <p className="guardian-push-prompt-error" role="alert">{error}</p> : null}
      <div className="guardian-push-prompt-actions">
        <button type="button" className="primary" onClick={() => void enable()} disabled={saving}>{saving ? "설정 중…" : mode === "disabled" ? "알림 다시 켜기" : "피드 알림 켜기"}</button>
        <button type="button" className="secondary" onClick={() => void close()} disabled={saving}>나중에</button>
      </div>
      <small>언제든 알림함에서 기기 알림을 변경할 수 있어요.</small>
    </section>
  </div>;
}

export function GuardianPushToggle({ supabase }: { supabase: SupabaseClient }) {
  const [state, setState] = useState<State>("checking");
  const [guardian, setGuardian] = useState(false);
  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(async ({ data }) => {
      const user = data.user;
      if (!active || !user) return;
      const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
      if (!active || profile?.role !== "guardian") return;
      setGuardian(true);
      if (!supportsPush()) { setState("unsupported"); return; }
      const registration = await navigator.serviceWorker.register("/push-service-worker.js");
      const subscription = await registration.pushManager.getSubscription();
      if (active) setState(subscription ? "on" : "off");
    }).catch(() => { if (active) setState("error"); });
    return () => { active = false; };
  }, [supabase]);

  async function toggle() {
    if (state !== "on" && state !== "off" && state !== "error") return;
    setState("saving");
    try {
      const registration = await navigator.serviceWorker.register("/push-service-worker.js");
      const existing = await registration.pushManager.getSubscription();
      if (existing) {
        const { error } = await supabase.from("push_subscriptions").delete().eq("endpoint", existing.endpoint);
        if (error) throw error;
        await existing.unsubscribe();
        await rememberPromptChoice(supabase, { [WAS_ENABLED_KEY]: true, [DISABLED_PROMPT_SEEN_KEY]: true });
        setState("off"); return;
      }
      await subscribeToGuardianPush(supabase);
      await rememberPromptChoice(supabase, { [WAS_ENABLED_KEY]: true, [DISABLED_PROMPT_SEEN_KEY]: false });
      setState("on");
    } catch { setState("error"); }
  }

  if (!guardian || state === "checking") return null;
  return <div className="guardian-push-setting"><button type="button" className={`guardian-push-toggle ${state}`} onClick={() => void toggle()} disabled={state === "saving" || state === "unsupported"} aria-pressed={state === "on"}>
    <span aria-hidden="true">{state === "on" ? "●" : "○"}</span>{state === "saving" ? "설정 중…" : state === "on" ? "기기 알림 켜짐" : state === "unsupported" ? "이 기기에서는 알림을 지원하지 않아요" : state === "error" ? "기기 알림 다시 시도" : "이 기기에서 알림 받기"}
  </button></div>;
}
