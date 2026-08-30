"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type State = "checking" | "unsupported" | "off" | "on" | "saving" | "error";
type PromptMode = "intro" | "weekly" | "disabled";
type DisabledState = "permission-off" | "subscription-missing";
const VAPID_PUBLIC_KEY = "BFtcz-HAAEgZVonjdQqk8hpZQwOMeQZObsTlL-jwoh_fdn9rWyt_GmaDOy77HEKQQ0qFazh-7PIGKtRB3BIfkuE";
const GUIDE_SEEN_KEY = "guardian_push_guide_seen";
const LAST_PROMPTED_KEY = "guardian_push_last_prompted_at";
const WAS_ENABLED_KEY = "guardian_push_was_enabled";
const DISABLED_PROMPT_STATE_KEY = "guardian_push_disabled_prompt_state";
const INTENTIONALLY_DISABLED_KEY = "guardian_push_intentionally_disabled";
const STAFF_GUIDE_SEEN_KEY = "staff_push_guide_seen";
const STAFF_LAST_PROMPTED_KEY = "staff_push_last_prompted_at";
const STAFF_WAS_ENABLED_KEY = "staff_push_was_enabled";
const STAFF_DISABLED_PROMPT_STATE_KEY = "staff_push_disabled_prompt_state";
const STAFF_INTENTIONALLY_DISABLED_KEY = "staff_push_intentionally_disabled";
const STAFF_PUSH_PROMPT_MEDIA = "(max-width: 767px)";
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const PUSH_ROLES = new Set(["guardian", "teacher", "assistant", "admin", "manager"]);

function decodeKey(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(normalized), (character) => character.charCodeAt(0));
}

function supportsPush() {
  return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
}

async function syncDeviceSubscription(supabase: SupabaseClient, subscription: PushSubscription, enabled = true) {
  const json = subscription.toJSON();
  if (enabled && (!json.keys?.p256dh || !json.keys.auth)) throw new Error("구독 정보를 확인할 수 없습니다.");
  const { error } = await supabase.rpc("set_current_device_push_subscription", {
    p_endpoint: subscription.endpoint,
    p_p256dh: enabled ? json.keys?.p256dh ?? null : null,
    p_auth: enabled ? json.keys?.auth ?? null : null,
    p_user_agent: navigator.userAgent,
    p_enabled: enabled,
  });
  if (error) throw error;
}

async function subscribeToDevicePush(supabase: SupabaseClient) {
  if (!supportsPush()) throw new Error("이 기기에서는 알림을 사용할 수 없습니다.");
  // iOS only allows the permission prompt while the button's user activation
  // is still alive. Ask before awaiting service-worker registration.
  if (Notification.permission !== "granted") {
    const permission = await Notification.requestPermission();
    if (permission !== "granted") throw new Error("기기 설정에서 알림을 허용해 주세요.");
  }
  const registration = await navigator.serviceWorker.register("/push-service-worker.js");
  let subscription = await registration.pushManager.getSubscription();
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: decodeKey(VAPID_PUBLIC_KEY) });
  }
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    await subscription.unsubscribe();
    throw new Error("구독 정보를 확인할 수 없습니다.");
  }
  try { await syncDeviceSubscription(supabase, subscription); }
  catch (error) { await subscription.unsubscribe(); throw error; }
  return subscription;
}

export function PushDeviceAccountSync({ supabase }: { supabase: SupabaseClient }) {
  useEffect(() => {
    let active = true;
    void (async () => {
      if (!supportsPush()) return;
      const [{ data: { user } }, registration] = await Promise.all([
        supabase.auth.getUser(),
        navigator.serviceWorker.register("/push-service-worker.js"),
      ]);
      if (!active || !user) return;
      const subscription = await registration.pushManager.getSubscription();
      if (!subscription) return;
      const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
      if (!active) return;
      const eligible = PUSH_ROLES.has(String(profile?.role ?? "")) && Notification.permission === "granted";
      await syncDeviceSubscription(supabase, subscription, eligible);
      if (!eligible && Notification.permission !== "granted") try { await subscription.unsubscribe(); } catch { /* The OS may already have revoked it. */ }
    })().catch(() => { /* Push ownership sync must never block the app. */ });
    return () => { active = false; };
  }, [supabase]);
  return null;
}

async function rememberPromptChoice(supabase: SupabaseClient, data: Record<string, boolean | string>, guideSeenKey = GUIDE_SEEN_KEY, lastPromptedKey = LAST_PROMPTED_KEY) {
  const { error } = await supabase.auth.updateUser({ data: {
    [guideSeenKey]: true,
    [lastPromptedKey]: new Date().toISOString(),
    ...data,
  } });
  if (error) throw error;
}

export function GuardianPushPrompt({ supabase, role = "guardian" }: { supabase: SupabaseClient; role?: string }) {
  const staff = role !== "guardian";
  const guideSeenKey = staff ? STAFF_GUIDE_SEEN_KEY : GUIDE_SEEN_KEY;
  const lastPromptedKey = staff ? STAFF_LAST_PROMPTED_KEY : LAST_PROMPTED_KEY;
  const wasEnabledKey = staff ? STAFF_WAS_ENABLED_KEY : WAS_ENABLED_KEY;
  const disabledPromptStateKey = staff ? STAFF_DISABLED_PROMPT_STATE_KEY : DISABLED_PROMPT_STATE_KEY;
  const intentionallyDisabledKey = staff ? STAFF_INTENTIONALLY_DISABLED_KEY : INTENTIONALLY_DISABLED_KEY;
  const [mode, setMode] = useState<PromptMode | null>(null);
  const [disabledState, setDisabledState] = useState<DisabledState | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [staffMobilePrompt, setStaffMobilePrompt] = useState(!staff);

  useEffect(() => {
    if (!staff) return;
    const media = window.matchMedia(STAFF_PUSH_PROMPT_MEDIA);
    const update = () => {
      setStaffMobilePrompt(media.matches);
      if (!media.matches) setMode(null);
    };
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [staff]);

  useEffect(() => {
    if (staff && !staffMobilePrompt) return;
    let active = true;
    void supabase.auth.getUser().then(async ({ data }) => {
      const user = data.user;
      if (!active || !user || !supportsPush()) return;
      const registration = await navigator.serviceWorker.register("/push-service-worker.js");
      const subscription = await registration.pushManager.getSubscription();
      const enabled = Boolean(subscription && Notification.permission === "granted");
      const metadata = user.user_metadata ?? {};
      if (enabled) {
        if (metadata[wasEnabledKey] !== true || metadata[disabledPromptStateKey] || metadata[intentionallyDisabledKey] === true) {
          await supabase.auth.updateUser({ data: {
            [wasEnabledKey]: true,
            [disabledPromptStateKey]: "",
            [intentionallyDisabledKey]: false,
          } });
        }
        return;
      }
      if (subscription && Notification.permission !== "granted") {
        await supabase.from("push_subscriptions").delete().eq("profile_id", user.id).eq("endpoint", subscription.endpoint);
        try { await subscription.unsubscribe(); } catch { /* The OS may already have revoked it. */ }
      }
      if (!active) return;
      if (metadata[intentionallyDisabledKey] === true) return;
      if (metadata[wasEnabledKey] === true) {
        const currentDisabledState: DisabledState = Notification.permission === "granted" ? "subscription-missing" : "permission-off";
        if (metadata[disabledPromptStateKey] !== currentDisabledState) {
          setDisabledState(currentDisabledState);
          setMode("disabled");
        }
        return;
      }
      if (metadata[guideSeenKey] !== true) { setMode("intro"); return; }
      const lastPrompted = Date.parse(String(metadata[lastPromptedKey] ?? ""));
      if (!Number.isFinite(lastPrompted) || Date.now() - lastPrompted >= WEEK_MS) setMode("weekly");
    }).catch(() => { /* Keep the app usable if push status cannot be checked. */ });
    return () => { active = false; };
  }, [disabledPromptStateKey, guideSeenKey, intentionallyDisabledKey, lastPromptedKey, staff, staffMobilePrompt, supabase, wasEnabledKey]);

  const close = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    try {
      await rememberPromptChoice(supabase, mode === "disabled" && disabledState ? { [disabledPromptStateKey]: disabledState } : {}, guideSeenKey, lastPromptedKey);
      setMode(null);
    }
    catch { setError("선택을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요."); }
    finally { setSaving(false); }
  }, [disabledPromptStateKey, disabledState, guideSeenKey, lastPromptedKey, mode, saving, supabase]);

  const enable = useCallback(async () => {
    if (saving) return;
    setSaving(true); setError("");
    try {
      // iOS requires the permission request to remain in the direct button gesture.
      await subscribeToDevicePush(supabase);
      await rememberPromptChoice(supabase, {
        [wasEnabledKey]: true,
        [disabledPromptStateKey]: "",
        [intentionallyDisabledKey]: false,
      }, guideSeenKey, lastPromptedKey);
      setMode(null);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "알림을 켜지 못했습니다.");
    }
    finally { setSaving(false); }
  }, [disabledPromptStateKey, disabledState, guideSeenKey, intentionallyDisabledKey, lastPromptedKey, mode, saving, supabase, wasEnabledKey]);

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
      <h2 id="guardian-push-title">{mode === "disabled" ? <>기기 알림이 꺼져 있어요<br />다시 연결해 드릴까요?</> : staff ? <>새 학부모 댓글을<br />바로 알려드릴게요</> : <>아이의 새 학습 기록을<br />바로 알려드릴게요</>}</h2>
      <p id="guardian-push-description">{mode === "disabled" ? <>알림 설정이 꺼진 것을 확인했어요.<br />다시 켜면 새 알림을 바로 받을 수 있어요.</> : staff ? <>담당 학생의 학습 피드에 댓글이 달리면<br />이 기기에서 빠르게 확인할 수 있어요.</> : <>수업·첨삭 리포트가 등록되면<br />이 기기에서 빠르게 확인할 수 있어요.</>}</p>
      {error ? <p className="guardian-push-prompt-error" role="alert">{error}</p> : null}
      <div className="guardian-push-prompt-actions">
        <button type="button" className="primary" onClick={() => void enable()} disabled={saving}>{saving ? "설정 중…" : mode === "disabled" ? "알림 다시 켜기" : staff ? "댓글 알림 켜기" : "피드 알림 켜기"}</button>
        <button type="button" className="secondary" onClick={() => void close()} disabled={saving}>나중에</button>
      </div>
      <small>언제든 알림함에서 기기 알림을 변경할 수 있어요.</small>
    </section>
  </div>;
}

export function DevicePushToggle({ supabase }: { supabase: SupabaseClient }) {
  const [state, setState] = useState<State>("checking");
  const [role, setRole] = useState("");
  useEffect(() => {
    let active = true;
    void supabase.auth.getUser().then(async ({ data }) => {
      const user = data.user;
      if (!active || !user) return;
      const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).maybeSingle();
      const currentRole=String(profile?.role??"");
      if (!active || !PUSH_ROLES.has(currentRole)) return;
      setRole(currentRole);
      if (!supportsPush()) { setState("unsupported"); return; }
      const registration = await navigator.serviceWorker.register("/push-service-worker.js");
      const subscription = await registration.pushManager.getSubscription();
      if (subscription && Notification.permission === "granted") await syncDeviceSubscription(supabase, subscription);
      if (active) setState(subscription && Notification.permission === "granted" ? "on" : "off");
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
        await syncDeviceSubscription(supabase, existing, false);
        await existing.unsubscribe();
        await rememberPromptChoice(supabase, {
          [WAS_ENABLED_KEY]: true,
          [DISABLED_PROMPT_STATE_KEY]: "",
          [INTENTIONALLY_DISABLED_KEY]: true,
        });
        setState("off"); return;
      }
      await subscribeToDevicePush(supabase);
      await rememberPromptChoice(supabase, {
        [WAS_ENABLED_KEY]: true,
        [DISABLED_PROMPT_STATE_KEY]: "",
        [INTENTIONALLY_DISABLED_KEY]: false,
      });
      setState("on");
    } catch { setState("error"); }
  }

  if (!role || state === "checking") return null;
  const staff=role!=="guardian";
  const description = state === "saving" ? "알림 설정을 변경하고 있어요" : state === "on" ? staff?"새 학부모 댓글을 이 기기에서 받아요":"새 학습 피드와 답장을 이 기기에서 받아요" : state === "unsupported" ? "이 기기에서는 알림을 지원하지 않아요" : state === "error" ? "iPhone 설정을 확인한 뒤 다시 시도해 주세요" : staff?"새 학부모 댓글 알림을 받을 수 있어요":"새 학습 피드와 답장 알림을 받을 수 있어요";
  return <div className={`guardian-push-setting ${state}`}>
    <div className="guardian-push-setting-icon" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z"/><path d="M10 21h4"/></svg>
    </div>
    <div className="guardian-push-setting-copy"><b>기기 알림</b><span>{description}</span></div>
    <button type="button" className="guardian-push-switch" onClick={() => void toggle()} disabled={state === "saving" || state === "unsupported"} aria-pressed={state === "on"} aria-label={state === "on" ? "기기 알림 끄기" : "기기 알림 켜기"}>
      <i aria-hidden="true" />
    </button>
  </div>;
}
