"use client";

import type { FormEvent } from "react";
import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import styles from "./my-account.module.css";

const roleLabels = {
  admin: "관리자",
  teacher: "교사",
  student: "학생",
  guardian: "학부모",
} as const;

function ProfileIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="8" r="3.25" />
      <path d="M5.75 19c.55-3.1 2.7-5 6.25-5s5.7 1.9 6.25 5" />
    </svg>
  );
}
function LockIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="5" y="10" width="14" height="10" rx="2.5" />
      <path d="M8.5 10V7.5a3.5 3.5 0 0 1 7 0V10M12 14v2.5" />
    </svg>
  );
}

export function MyAccount({ supabase, profile, email, onProfileUpdated }: { supabase: SupabaseClient; profile: Profile; email: string; onProfileUpdated: (displayName: string) => void }) {
  const [displayName, setDisplayName] = useState(profile.display_name);
  const [phone, setPhone] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [changing, setChanging] = useState(false);
  const [passwordMessage, setPasswordMessage] = useState("");
  const [passwordError, setPasswordError] = useState("");
  useEffect(() => {
    let active = true;
    void supabase
      .from("profiles")
      .select("display_name,phone")
      .eq("id", profile.id)
      .single()
      .then(({ data, error: loadError }) => {
        if (!active) return;
        if (loadError) setError("내 계정 정보를 불러오지 못했습니다.");
        else {
          setDisplayName(data.display_name);
          setPhone(data.phone ?? "");
        }
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [profile.id, supabase]);
  const saveProfile = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    setError("");
    setMessage("");
    const { error: saveError } = await supabase.rpc("save_my_account", {
      p_display_name: displayName,
      p_phone: phone || null,
    });
    if (saveError) setError(readError(saveError.message, "내 정보를 저장하지 못했습니다."));
    else {
      const trimmed = displayName.trim();
      onProfileUpdated(trimmed);
      setDisplayName(trimmed);
      setMessage(profile.role === "student" ? "연락처를 저장했습니다." : "이름과 연락처를 저장했습니다.");
    }
    setSaving(false);
  };
  const changePassword = async (event: FormEvent) => {
    event.preventDefault();
    setPasswordError("");
    setPasswordMessage("");
    if (newPassword.length < 8) {
      setPasswordError("새 비밀번호는 8자 이상 입력해 주세요.");
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError("새 비밀번호 확인이 일치하지 않습니다.");
      return;
    }
    if (currentPassword === newPassword) {
      setPasswordError("현재 비밀번호와 다른 비밀번호를 입력해 주세요.");
      return;
    }
    setChanging(true);
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password: currentPassword,
    });
    if (signInError) {
      setPasswordError("현재 비밀번호가 맞지 않습니다.");
      setChanging(false);
      return;
    }
    const { error: updateError } = await supabase.auth.updateUser({
      password: newPassword,
    });
    if (updateError) setPasswordError(readError(updateError.message, "비밀번호를 변경하지 못했습니다."));
    else {
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setPasswordMessage("비밀번호를 변경했습니다. 다음 로그인부터 새 비밀번호를 사용하세요.");
    }
    setChanging(false);
  };

  return (
    <div className={styles.page}>
      <div className={styles.heading}>
        <p className={styles.eyebrow}>개인 설정</p>
        <h1>내 계정</h1>
        <p>내 정보와 로그인 보안을 한곳에서 관리합니다.</p>
      </div>
      <div className={styles.grid}>
        <section className={styles.card}>
          <header className={styles.cardHeader}>
            <span className={styles.icon}>
              <ProfileIcon />
            </span>
            <div>
              <h2>기본 정보</h2>
              <p>학원 화면에 표시되는 계정 정보입니다.</p>
            </div>
          </header>
          {loading ? (
            <p className={styles.loading}>계정 정보를 불러오는 중이에요…</p>
          ) : (
            <form className={styles.form} onSubmit={saveProfile}>
              <div className={styles.readonlyGrid}>
                <label>
                  로그인 이메일
                  <input disabled value={email} />
                </label>
                <label>
                  계정 역할
                  <input disabled value={roleLabels[profile.role]} />
                </label>
              </div>
              <label>
                표시 이름 <b>*</b>
                <input required disabled={profile.role === "student"} value={displayName} onChange={(event) => setDisplayName(event.target.value)} />
                {profile.role === "student" && <small className={styles.hint}>학생 이름은 관리자만 변경할 수 있습니다.</small>}
              </label>
              <label>
                연락처
                <input inputMode="tel" value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="010-0000-0000" />
              </label>
              {error && <p className="form-error">{error}</p>}
              {message && <p className={styles.success}>{message}</p>}
              <div className={styles.actions}>
                <button className="primary" disabled={saving}>
                  {saving ? "저장 중…" : "내 정보 저장"}
                </button>
              </div>
            </form>
          )}
        </section>
        <section className={styles.card}>
          <header className={styles.cardHeader}>
            <span className={styles.icon}>
              <LockIcon />
            </span>
            <div>
              <h2>비밀번호 변경</h2>
              <p>안전한 비밀번호로 로그인 정보를 보호하세요.</p>
            </div>
          </header>
          <form className={styles.form} onSubmit={changePassword}>
            <label>
              현재 비밀번호
              <input required type="password" autoComplete="current-password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} placeholder="현재 비밀번호 입력" />
            </label>
            <div className={styles.passwordGrid}>
              <label>
                새 비밀번호 <b>*</b>
                <input required minLength={8} type="password" autoComplete="new-password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} placeholder="8자 이상" />
              </label>
              <label>
                새 비밀번호 확인 <b>*</b>
                <input required minLength={8} type="password" autoComplete="new-password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} placeholder="한 번 더 입력" />
              </label>
            </div>
            <p className={styles.hint}>영문·숫자·특수문자를 조합하면 더 안전합니다.</p>
            {passwordError && <p className="form-error">{passwordError}</p>}
            {passwordMessage && <p className={styles.success}>{passwordMessage}</p>}
            <div className={styles.actions}>
              <button className="primary" disabled={changing}>
                {changing ? "변경 중…" : "비밀번호 변경"}
              </button>
            </div>
          </form>
        </section>
      </div>
    </div>
  );
}

function readError(message: string, fallback: string) {
  return ["이름", "연락처", "비밀번호", "Password", "password", "same"].some((word) => message.includes(word)) ? message : fallback;
}
