"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

const CHECK_INTERVAL_MS = 5 * 60 * 1000;
const IDLE_RECHECK_MS = 30 * 1000;
const STARTUP_WINDOW_MS = 2 * 60 * 1000;
const APPLIED_VERSION_KEY = "hansalmae:app-update-applied";
const SCROLL_RESET_KEY = "hansalmae:app-update-scroll-reset";

function koreaHour() {
  return Number(new Intl.DateTimeFormat("en-GB", {
    timeZone: "Asia/Seoul",
    hour: "2-digit",
    hour12: false,
  }).format(new Date()));
}

function hasUnsavedWork() {
  if (document.querySelector(".modal-backdrop, .nested-modal-backdrop, [role='dialog'], [role='alertdialog']")) return true;
  const focusedControl = document.querySelector("input:focus, textarea:focus, select:focus, [contenteditable='true']:focus");
  // Remembered credentials and typing on the login screen are safe to discard:
  // the browser/password manager keeps them, and they must never trap an old
  // application bundle behind the update prompt.
  if (focusedControl && !focusedControl.closest(".login-card")) return true;

  // Navigation filters and the guardian child selector are controlled fields too,
  // but changing them does not create unsaved work. Only compare fields that
  // belong to an actual form so those persistent UI controls cannot block an update.
  return Array.from(document.querySelectorAll<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>("form input, form textarea, form select")).some((field) => {
    if (field.closest(".login-card")) return false;
    if (field.disabled || field.type === "hidden" || field.type === "button" || field.type === "submit") return false;
    if (field instanceof HTMLInputElement && (field.type === "checkbox" || field.type === "radio")) {
      return field.checked !== field.defaultChecked;
    }
    if (field instanceof HTMLSelectElement) {
      return Array.from(field.options).some((option) => option.selected !== option.defaultSelected);
    }
    return field.value !== field.defaultValue;
  });
}

export function AppUpdateManager({ currentVersion }: { currentVersion: string }) {
  const [availableVersion, setAvailableVersion] = useState("");
  const [waitingForSave, setWaitingForSave] = useState(false);
  const mountedAt = useRef(0);
  const reloading = useRef(false);

  useLayoutEffect(() => {
    if (window.sessionStorage.getItem(SCROLL_RESET_KEY) !== currentVersion) return;

    const previousRestoration = window.history.scrollRestoration;
    window.history.scrollRestoration = "manual";
    let cancelled = false;
    const resetScroll = () => {
      if (!cancelled) window.scrollTo({ top: 0, left: 0, behavior: "auto" });
    };
    const timers = [0, 80, 250, 600, 1200, 2200].map((delay) => window.setTimeout(resetScroll, delay));
    const finish = () => {
      if (cancelled) return;
      cancelled = true;
      timers.forEach((timer) => window.clearTimeout(timer));
      window.sessionStorage.removeItem(SCROLL_RESET_KEY);
      window.history.scrollRestoration = previousRestoration;
    };
    const finishTimer = window.setTimeout(finish, 2400);
    window.addEventListener("pageshow", resetScroll);
    window.addEventListener("touchstart", finish, { once: true, passive: true });
    window.addEventListener("wheel", finish, { once: true, passive: true });
    resetScroll();

    return () => {
      cancelled = true;
      timers.forEach((timer) => window.clearTimeout(timer));
      window.clearTimeout(finishTimer);
      window.removeEventListener("pageshow", resetScroll);
      window.removeEventListener("touchstart", finish);
      window.removeEventListener("wheel", finish);
      window.history.scrollRestoration = previousRestoration;
    };
  }, [currentVersion]);

  const reloadWithVersion = useCallback(() => {
    if (reloading.current || !availableVersion) return;
    reloading.current = true;
    window.history.scrollRestoration = "manual";
    window.scrollTo({ top: 0, left: 0, behavior: "auto" });
    window.sessionStorage.setItem(APPLIED_VERSION_KEY, availableVersion);
    window.sessionStorage.setItem(SCROLL_RESET_KEY, availableVersion);
    window.location.reload();
  }, [availableVersion]);

  const applyUpdate = useCallback(() => {
    if (reloading.current || !availableVersion) return;
    if (hasUnsavedWork()) {
      setWaitingForSave(true);
      return;
    }
    reloadWithVersion();
  }, [availableVersion, reloadWithVersion]);

  const checkVersion = useCallback(async () => {
    try {
      const response = await fetch(`/api/app-version?t=${Date.now()}`, { cache: "no-store" });
      if (!response.ok) return;
      const payload = await response.json() as { version?: string };
      const latest = payload.version ?? "";
      if (!latest || latest === "development" || latest === currentVersion) return;
      if (window.sessionStorage.getItem(APPLIED_VERSION_KEY) === latest) return;
      setAvailableVersion(latest);

      const justOpened = Date.now() - mountedAt.current <= STARTUP_WINDOW_MS;
      if ((justOpened || koreaHour() === 4) && !hasUnsavedWork()) {
        reloading.current = true;
        window.history.scrollRestoration = "manual";
        window.scrollTo({ top: 0, left: 0, behavior: "auto" });
        window.sessionStorage.setItem(APPLIED_VERSION_KEY, latest);
        window.sessionStorage.setItem(SCROLL_RESET_KEY, latest);
        window.location.reload();
      }
    } catch {
      // Offline and temporary network failures are retried on the next check.
    }
  }, [currentVersion]);

  useEffect(() => {
    mountedAt.current = Date.now();
    void checkVersion();
    const timer = window.setInterval(() => void checkVersion(), CHECK_INTERVAL_MS);
    const refresh = () => {
      if (document.visibilityState === "visible") void checkVersion();
    };
    window.addEventListener("focus", refresh);
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", refresh);
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [checkVersion]);

  useEffect(() => {
    if (!availableVersion) return;
    const tryScheduledUpdate = () => {
      if ((waitingForSave || koreaHour() === 4) && !hasUnsavedWork()) applyUpdate();
    };
    const timer = window.setInterval(tryScheduledUpdate, IDLE_RECHECK_MS);
    document.addEventListener("focusout", tryScheduledUpdate);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener("focusout", tryScheduledUpdate);
    };
  }, [applyUpdate, availableVersion, waitingForSave]);

  if (!availableVersion) return null;

  return (
    <aside className="app-update-toast" role="status" aria-live="polite">
      <span>
        <b>{waitingForSave ? "작성 중인 내용을 먼저 저장해 주세요" : "새 버전이 준비됐어요"}</b>
        <small>{waitingForSave ? "저장하거나 창을 닫으면 자동으로 적용됩니다." : "지금 업데이트해도 로그인은 유지됩니다."}</small>
      </span>
      <button type="button" onClick={waitingForSave ? reloadWithVersion : applyUpdate}>{waitingForSave ? "저장 완료 후 업데이트" : "지금 업데이트"}</button>
    </aside>
  );
}
