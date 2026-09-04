"use client";

import type { ReactNode } from "react";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import Image from "next/image";

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

type InstallWindow = Window & {
  __hansalmaeInstallPrompt?: InstallPromptEvent | null;
  __hansalmaeAutoInstall?: boolean;
};

const KAKAO_INSTALL_HIDDEN_KEY = "hansalmae:kakao-install-button-hidden";
const INSTALL_VISIBILITY_EVENT = "hansalmae:install-visibility-change";

function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches ||
    Boolean((navigator as Navigator & { standalone?: boolean }).standalone);
}

function isAndroidInAppBrowser(ua: string) {
  return /Android/i.test(ua) && /KAKAOTALK|DaumApps|NAVER|Instagram|FBAN|FBAV|Line\//i.test(ua);
}

function isKakaoInAppBrowser(ua = navigator.userAgent) {
  return /KAKAOTALK|DaumApps/i.test(ua);
}

function openAndroidChromeInstallFlow() {
  const url = new URL(window.location.href);
  url.searchParams.set("install", "1");
  const fallbackUrl = url.toString();
  const scheme = url.protocol.replace(":", "");
  const target = `${url.host}${url.pathname}${url.search}${url.hash}`;
  const intentUrl = `intent://${target}#Intent;scheme=${scheme};package=com.android.chrome;S.browser_fallback_url=${encodeURIComponent(fallbackUrl)};end`;
  window.location.href = intentUrl;
}

async function prepareAndroidInstall() {
  if (!("serviceWorker" in navigator)) return;
  try {
    const registration = await navigator.serviceWorker.register("/push-service-worker.js");
    await navigator.serviceWorker.ready;
    void registration.update().catch(() => undefined);
  } catch {
    // Installation UI below explains unsupported browser states.
  }
}

export function AppInstallPrompt({ placement = "login" }: { placement?: "login" | "topbar" }) {
  const [device, setDevice] = useState<"android" | "ios" | "desktop" | null>(null);
  const [installPrompt, setInstallPrompt] = useState<InstallPromptEvent | null>(null);
  const [guide, setGuide] = useState<"ios" | null>(null);
  const [installed, setInstalled] = useState(false);
  const [installing, setInstalling] = useState(false);
  const [androidMessage, setAndroidMessage] = useState("");
  const [androidGuide, setAndroidGuide] = useState<"direct" | "kakao" | null>(null);
  const [attention, setAttention] = useState(false);
  const [hiddenInKakao, setHiddenInKakao] = useState(false);
  const [confirmInstalled, setConfirmInstalled] = useState(false);

  useEffect(() => {
    setInstalled(isStandalone());

    const ua = navigator.userAgent;
    const android = /Android/i.test(ua);
    if (/iPhone|iPad|iPod/i.test(ua)) setDevice("ios");
    else if (android) setDevice("android");
    else setDevice("desktop");

    let syncVisibility: (() => void) | null = null;
    if (placement === "topbar") {
      setAttention(window.sessionStorage.getItem("hansalmae:install-button-seen") !== "1");
      syncVisibility = () => setHiddenInKakao(isKakaoInAppBrowser(ua) && window.localStorage.getItem(KAKAO_INSTALL_HIDDEN_KEY) === "1");
      syncVisibility();
      window.addEventListener(INSTALL_VISIBILITY_EVENT, syncVisibility);
    }

    const installWindow = window as InstallWindow;
    const installRequested = android && new URL(window.location.href).searchParams.get("install") === "1";
    if (installRequested) installWindow.__hansalmaeAutoInstall = true;

    if (installWindow.__hansalmaeInstallPrompt) {
      setInstallPrompt(installWindow.__hansalmaeInstallPrompt);
      if (installRequested) {
        installWindow.__hansalmaeAutoInstall = false;
        setAndroidGuide("direct");
      }
    }

    const receivePrompt = (event: Event) => {
      event.preventDefault();
      const promptEvent = event as InstallPromptEvent;
      installWindow.__hansalmaeInstallPrompt = promptEvent;
      setInstallPrompt(promptEvent);
      setAndroidMessage("");

      if (installWindow.__hansalmaeAutoInstall) {
        installWindow.__hansalmaeAutoInstall = false;
        setAndroidGuide("direct");
      }
    };

    const finishInstall = () => {
      installWindow.__hansalmaeInstallPrompt = null;
      installWindow.__hansalmaeAutoInstall = false;
      setInstallPrompt(null);
      setInstalled(true);
    };

    window.addEventListener("beforeinstallprompt", receivePrompt);
    window.addEventListener("appinstalled", finishInstall);

    if (android) void prepareAndroidInstall();

    return () => {
      window.removeEventListener("beforeinstallprompt", receivePrompt);
      window.removeEventListener("appinstalled", finishInstall);
      if (syncVisibility) window.removeEventListener(INSTALL_VISIBILITY_EVENT, syncVisibility);
    };
  }, [placement]);

  if (!device || device === "desktop" || installed || hiddenInKakao) return null;

  const launchAndroidPrompt = async (promptEvent: InstallPromptEvent) => {
    setInstalling(true);
    try {
      await promptEvent.prompt();
      const choice = await promptEvent.userChoice;
      (window as InstallWindow).__hansalmaeInstallPrompt = null;
      setInstallPrompt(null);
      if (choice.outcome === "accepted") setInstalled(true);
    } finally {
      setInstalling(false);
    }
  };

  const openInstall = async () => {
    if (placement === "topbar") {
      window.sessionStorage.setItem("hansalmae:install-button-seen", "1");
      setAttention(false);
    }
    if (device === "ios") {
      setGuide("ios");
      return;
    }
    if (installing) return;

    setAndroidMessage("");

    if (isStandalone()) {
      setInstalled(true);
      return;
    }

    const ua = navigator.userAgent;
    const promptEvent = installPrompt ?? (window as InstallWindow).__hansalmaeInstallPrompt ?? null;

    if (device === "android" && isKakaoInAppBrowser(ua)) {
      setAndroidGuide("kakao");
      return;
    }

    if (promptEvent) {
      setAndroidGuide("direct");
      return;
    }

    if (isAndroidInAppBrowser(ua)) {
      // KakaoTalk/Naver/etc. cannot expose beforeinstallprompt reliably.
      // Hand the same user tap directly to Android Chrome and request installation there.
      (window as InstallWindow).__hansalmaeAutoInstall = true;
      openAndroidChromeInstallFlow();
      return;
    }

    setAndroidMessage("Chrome에서 페이지를 한 번 새로고침한 뒤 설치 버튼을 눌러 주세요.");
  };

  return (
    <>
      <button
        type="button"
        className={`app-install-button${placement === "topbar" ? ` app-install-topbar${attention ? " is-calling" : ""}` : ""}`}
        disabled={installing}
        onClick={() => void openInstall()}
        aria-label={installing ? "앱 설치창 여는 중" : "한살매 수업노트 앱 설치"}
      >
        <span className="app-install-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none"><path d="M12 3v11m0 0 4-4m-4 4-4-4M5 15v3.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V15" /></svg>
        </span>
        <span><b>{installing ? "설치 중…" : placement === "topbar" ? "앱 설치" : "한살매 수업노트 설치"}</b><small>{device === "ios" ? "아이폰 홈 화면에 추가하기" : "안내 확인 후 안드로이드에 설치하기"}</small></span>
        <i aria-hidden="true">›</i>
      </button>
      {androidMessage && <p className="app-install-status" role="status">{androidMessage}</p>}

      {androidGuide && <InstallPortal>
        <div className="install-guide-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setAndroidGuide(null); }}>
          <section className="install-guide samsung-install-guide" role="dialog" aria-modal="true" aria-labelledby="samsung-install-title">
            <header>
              <Image className="install-guide-logo" src="/app-icon-192-v13.png" width={42} height={42} alt="" aria-hidden="true" />
              <div><small>설치 전 꼭 확인해 주세요</small><h2 id="samsung-install-title">안드로이드 설치 안내</h2></div>
              <button type="button" aria-label="설치 안내 닫기" onClick={() => setAndroidGuide(null)}>×</button>
            </header>
            <div className="samsung-install-body">
              {androidGuide === "kakao" && <div className="samsung-install-notice"><i aria-hidden="true">1</i><p><b>먼저 Chrome으로 이동합니다.</b><span>아래 버튼을 누르면 현재 화면을 Chrome으로 넘기고 설치를 이어서 진행합니다.</span></p></div>}
              <div className="samsung-install-notice"><i aria-hidden="true">!</i><p><b>설치 중 아래 보안 안내가 나타날 수 있어요.</b><span>안드로이드의 웹앱 설치 과정에서 표시되는 안내입니다. 그림에 표시된 순서대로 눌러 주세요.</span></p></div>
              <ol>
                <li>
                  <div><em>1</em><span><b>‘세부정보 더 보기’를 눌러 주세요</b><small>첫 번째 경고 화면 아래쪽에 있습니다.</small></span></div>
                  <div className="samsung-shot">
                    <Image src="/samsung-install-warning-step1.png" width={359} height={538} sizes="(max-width: 520px) 82vw, 330px" alt="Google Play 프로텍트 화면의 세부정보 더 보기" />
                    <span className="samsung-tap-marker step-one">여기를 누르세요</span>
                  </div>
                </li>
                <li>
                  <div><em>2</em><span><b>‘무시하고 설치하기’를 눌러 주세요</b><small>설치가 끝나면 홈 화면에 한살매노트가 생깁니다.</small></span></div>
                  <div className="samsung-shot">
                    <Image src="/samsung-install-warning-step2.png" width={359} height={538} sizes="(max-width: 520px) 82vw, 330px" alt="Google Play 프로텍트 화면의 무시하고 설치하기" />
                    <span className="samsung-tap-marker step-two">여기를 누르세요</span>
                  </div>
                </li>
              </ol>
              <p className="samsung-install-question">한살매 수업노트를 설치하시겠습니까?</p>
            </div>
            <footer className="samsung-install-actions">
              {androidGuide === "kakao" ? <button type="button" className="secondary-button installed-already" onClick={() => setConfirmInstalled(true)}>이미 설치했어요</button> : <button type="button" className="secondary-button" onClick={() => setAndroidGuide(null)}>취소</button>}
              <button type="button" onClick={() => {
                if (androidGuide === "kakao") {
                  openAndroidChromeInstallFlow();
                  return;
                }
                const promptEvent = installPrompt ?? (window as InstallWindow).__hansalmaeInstallPrompt ?? null;
                setAndroidGuide(null);
                if (promptEvent) void launchAndroidPrompt(promptEvent);
                else setAndroidMessage("Chrome에서 페이지를 한 번 새로고침한 뒤 설치 버튼을 눌러 주세요.");
              }}>{androidGuide === "kakao" ? "Chrome에서 설치 계속" : "설치 시작"}</button>
            </footer>
          </section>
        </div>
      </InstallPortal>}

      {guide && <InstallPortal>
        <div className="install-guide-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setGuide(null); }}>
          <section className="install-guide" role="dialog" aria-modal="true" aria-labelledby="install-guide-title">
            <header>
              <Image className="install-guide-logo" src="/app-icon-192-v13.png" width={42} height={42} alt="" aria-hidden="true" />
              <div><small>한살매 수업노트</small><h2 id="install-guide-title">{guide === "ios" ? "아이폰에 설치하기" : "앱으로 열기"}</h2></div>
              <button type="button" aria-label="설치 안내 닫기" onClick={() => setGuide(null)}>×</button>
            </header>
            <IosGuide />
            <footer className={isKakaoInAppBrowser() ? "install-guide-choice-actions" : ""}>
              {isKakaoInAppBrowser() && <button type="button" className="installed-already" onClick={() => setConfirmInstalled(true)}>이미 설치했어요</button>}
              <button type="button" onClick={() => {
                setGuide(null);
              }}>확인했어요</button>
            </footer>
          </section>
        </div>
      </InstallPortal>}
      {confirmInstalled && <InstallPortal>
        <div className="install-guide-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setConfirmInstalled(false); }}>
          <section className="install-installed-confirm" role="alertdialog" aria-modal="true" aria-labelledby="installed-confirm-title">
            <span className="app-install-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M5 12.5 10 17l9-10" /></svg></span>
            <h2 id="installed-confirm-title">한살매 앱이 홈 화면에 설치되어 있나요?</h2>
            <p>확인하면 카카오톡 화면에서는 앱 설치 버튼을 숨깁니다. 더보기에서 언제든 다시 표시할 수 있어요.</p>
            <div><button type="button" className="secondary-button" onClick={() => setConfirmInstalled(false)}>아니요, 돌아가기</button><button type="button" onClick={() => {
              window.localStorage.setItem(KAKAO_INSTALL_HIDDEN_KEY, "1");
              window.dispatchEvent(new Event(INSTALL_VISIBILITY_EVENT));
              setConfirmInstalled(false);
              setGuide(null);
              setAndroidGuide(null);
            }}>네, 설치되어 있어요</button></div>
          </section>
        </div>
      </InstallPortal>}
    </>
  );
}

export function KakaoInstallButtonRecovery() {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const sync = () => setVisible(!isStandalone() && isKakaoInAppBrowser() && window.localStorage.getItem(KAKAO_INSTALL_HIDDEN_KEY) === "1");
    sync();
    window.addEventListener(INSTALL_VISIBILITY_EVENT, sync);
    return () => window.removeEventListener(INSTALL_VISIBILITY_EVENT, sync);
  }, []);
  if (!visible) return null;
  return <button type="button" onClick={() => {
    window.localStorage.removeItem(KAKAO_INSTALL_HIDDEN_KEY);
    window.sessionStorage.removeItem("hansalmae:install-button-seen");
    window.dispatchEvent(new Event(INSTALL_VISIBILITY_EVENT));
  }}>
    <i aria-hidden="true">↓</i>
    <span><b>앱 설치 버튼 다시 표시</b><small>실수로 숨긴 설치 버튼을 상단에 다시 보여요.</small></span>
    <em>›</em>
  </button>;
}

function InstallPortal({ children }: { children: ReactNode }) {
  if (typeof document === "undefined") return null;
  return createPortal(children, document.body);
}

function IosGuide() {
  const ua = navigator.userAgent;
  const inAppBrowser = /KAKAOTALK|DaumApps|NAVER|Instagram|FBAN|FBAV|Line\/|GSA|CriOS|FxiOS|EdgiOS/i.test(ua);
  const safari = /Safari/i.test(ua) && !inAppBrowser;
  return <div className="install-guide-body">
    {!safari ? <SafariHandoff isKakao={/KAKAOTALK|DaumApps/i.test(ua)} /> : <SafariInstallSteps />}
  </div>;
}

function SafariHandoff({ isKakao }: { isKakao: boolean }) {
  return <div className="safari-handoff">
    <p className="install-guide-lead"><b>지금은 {isKakao ? "카카오톡" : "앱 내부"} 화면입니다.</b><br/>아이폰 설치는 Safari에서 진행해 주세요.</p>
    <ol className="install-steps handoff">
      <li><em>1</em><span><b>{isKakao ? "오른쪽 아래의 공유 버튼을 눌러 주세요" : "화면의 공유 버튼을 눌러 주세요"}</b><small>아래 그림과 같은 네모 위 화살표 모양입니다.</small></span><ShareIcon /></li>
      <li className="safari-choice-step"><em>2</em><span><b>공유 메뉴에서 ‘Safari로 열기’를 눌러 주세요</b></span><SafariShareMenu /></li>
      <li><em>3</em><span><b>Safari에서 설치 버튼을 다시 눌러 주세요</b><small>로그인 화면으로 이동하면 아래 설치 버튼을 한 번 더 누릅니다.</small></span><InstallButtonPreview /></li>
    </ol>
    <p className="install-safe-note emphasis">Safari에서 설치 버튼을 다시 누르면 ‘홈 화면에 추가’ 방법이 이어서 나옵니다.</p>
  </div>;
}

function ShareIcon() {
  return <i className="ios-share-icon" aria-label="아이폰 공유 아이콘"><svg viewBox="0 0 32 32" fill="none"><path d="M16 20V3m0 0-6 6m6-6 6 6M7 14H5.5A2.5 2.5 0 0 0 3 16.5v10A2.5 2.5 0 0 0 5.5 29h21a2.5 2.5 0 0 0 2.5-2.5v-10a2.5 2.5 0 0 0-2.5-2.5H25" /></svg></i>;
}

function SafariShareMenu() {
  return <div className="share-menu-photo" aria-label="공유 메뉴에서 Safari로 열기 선택">
    <Image src="/kakao-safari-share-menu.jpeg" width={1206} height={400} sizes="(max-width: 520px) 90vw, 420px" alt="Safari로 열기, URL 복사하기, 새로운 빠른 메모에 추가, 더 보기 메뉴" />
    <i aria-hidden="true" />
  </div>;
}

function InstallButtonPreview() {
  return <span className="install-button-preview"><i className="app-install-icon" aria-hidden="true"><svg viewBox="0 0 24 24" fill="none"><path d="M12 3v11m0 0 4-4m-4 4-4-4M5 15v3.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V15" /></svg></i><b>한살매 수업노트 설치</b></span>;
}

function SafariInstallSteps() {
  return <>
    <p className="install-guide-lead">Safari에서 아래 순서대로 누르면 홈 화면에 한살매 아이콘이 생깁니다.</p>
    <ol className="install-steps safari-install-steps">
      <li><em>1</em><span><b>오른쪽 아래의 ‘···’를 눌러 주세요</b><small>Safari 주소창 오른쪽에 있는 점 세 개 버튼입니다.</small></span><SafariStepImage src="/ios-safari-more-button.jpeg" width={220} height={302} alt="Safari 오른쪽 아래 점 세 개 버튼" marker="more-button" /></li>
      <li><em>2</em><span><b>메뉴 맨 위의 ‘공유’를 눌러 주세요</b><small>네모 위로 화살표가 올라가는 항목입니다.</small></span><SafariStepImage src="/ios-safari-share-action.jpeg" width={734} height={1045} alt="Safari 메뉴의 공유 항목" marker="share-action" /></li>
      <li><em>3</em><span><b>가로 메뉴 오른쪽의 ‘더 보기’를 눌러 주세요</b><small>아래쪽 화살표 모양의 마지막 항목입니다.</small></span><SafariStepImage src="/ios-safari-more-action.jpeg" width={1206} height={445} alt="공유 가로 메뉴의 더 보기 항목" marker="more-action" /></li>
      <li><em>4</em><span><b>펼쳐진 메뉴에서 ‘홈 화면에 추가’를 눌러 주세요</b><small>목록 아래쪽의 네모 안 ＋ 표시 항목입니다.</small></span><SafariStepImage src="/ios-safari-home-action.jpeg" width={1206} height={1251} alt="공유 메뉴의 홈 화면에 추가 항목" marker="home-action" /></li>
      <li><em>5</em><span><b>오른쪽 위의 파란색 ‘추가’를 눌러 주세요</b><small>완료되면 홈 화면의 한살매노트 아이콘으로 접속하세요.</small></span><SafariStepImage src="/ios-safari-add-action.jpeg" width={1206} height={907} alt="홈 화면에 추가 화면의 추가 버튼" marker="add-action" /></li>
    </ol>
    <p className="install-safe-note">App Store 검색은 필요 없으며, 기존 학생 정보와 로그인 정보는 그대로 유지됩니다.</p>
  </>;
}

function SafariStepImage({ src, width, height, alt, marker }: { src: string; width: number; height: number; alt: string; marker: string }) {
  return <span className={`safari-step-image ${marker}`}><Image src={src} width={width} height={height} sizes="(max-width: 520px) 82vw, 390px" alt={alt} /><i aria-hidden="true" /></span>;
}
