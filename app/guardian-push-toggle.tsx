"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type State = "checking" | "unsupported" | "off" | "on" | "saving" | "error";
const VAPID_PUBLIC_KEY = "BFtcz-HAAEgZVonjdQqk8hpZQwOMeQZObsTlL-jwoh_fdn9rWyt_GmaDOy77HEKQQ0qFazh-7PIGKtRB3BIfkuE";
const GUIDE_SEEN_KEY = "guardian_push_guide_seen";

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
    user_id: user.id, endpoint: subscription.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth, user_agent: navigator.userAgent,
  }, { onConflict: "endpoint" });
  if (error) { await subscription.unsubscribe(); throw error; }
  return subscription;
}

async function rememberGuideChoice(supabase: SupabaseClient) {
  const { error } = await supabase.auth.updateUser({ data: { [GUIDE_SEEN_KEY]: true } });
  if (error) throw error;
}

export function GuardianPushPrompt({ supabase }: { supabase: SupabaseClient }) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(({ data }) => {
      if (!active || !data.user || data.user.user_metadata?.[GUIDE_SEEN_KEY] === true) return;
      setOpen(true);
    });
    return () => { active = false; };
  }, [supabase]);

  const close = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    try { await rememberGuideChoice(supabase); setOpen(false); }
    catch { setError("선택을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요."); }
    finally { setSaving(false); }
  }, [saving, supabase]);

  const enable = useCallback(async () => {
    if (saving) return;
    setSaving(true); setError("");
    try {
      // iOS requires the permission request to remain in the direct button gesture.
      await subscribeToGuardianPush(supabase);
      await rememberGuideChoice(supabase);
      setOpen(false);
    } catch (caught) {
      try { await rememberGuideChoice(supabase); } catch { /* Keep the actionable push error visible. */ }
      setError(caught instanceof Error ? caught.message : "알림을 켜지 못했습니다.");
    }
    finally { setSaving(false); }
  }, [saving, supabase]);

  if (!open) return null;
  return <div className="guardian-push-prompt-backdrop" role="presentation">
    <section className="guardian-push-prompt" role="dialog" aria-modal="true" aria-labelledby="guardian-push-title" aria-describedby="guardian-push-description">
      <div className="guardian-push-prompt-icon" aria-hidden="true"><span>●</span></div>
      <p className="eyebrow">한살매 수업노트</p>
      <h2 id="guardian-push-title">아이의 새 학습 기록을<br />바로 알려드릴게요</h2>
      <p id="guardian-push-description">수업·첨삭 리포트가 등록되면<br />이 기기에서 빠르게 확인할 수 있어요.</p>
      {error ? <p className="guardian-push-prompt-error" role="alert">{error}</p> : null}
      <div className="guardian-push-prompt-actions">
        <button type="button" className="primary" onClick={() => void enable()} disabled={saving}>{saving ? "설정 중…" : "피드 알림 켜기"}</button>
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
        await existing.unsubscribe(); setState("off"); return;
      }
      await subscribeToGuardianPush(supabase); setState("on");
    } catch { setState("error"); }
  }

  if (!guardian || state === "checking") return null;
  return <div className="guardian-push-setting"><button type="button" className={`guardian-push-toggle ${state}`} onClick={() => void toggle()} disabled={state === "saving" || state === "unsupported"} aria-pressed={state === "on"}>
    <span aria-hidden="true">{state === "on" ? "●" : "○"}</span>{state === "saving" ? "설정 중…" : state === "on" ? "기기 알림 켜짐" : state === "unsupported" ? "이 기기에서는 알림을 지원하지 않아요" : state === "error" ? "기기 알림 다시 시도" : "이 기기에서 알림 받기"}
  </button></div>;
}
