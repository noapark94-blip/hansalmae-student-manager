"use client";

import { useEffect, useState } from "react";

type InstallPromptEvent = Event & {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
};

export function AppInstallPrompt() {
  const [device, setDevice] = useState<"android" | "ios" | null>(null);
  const [installPrompt, setInstallPrompt] = useState<InstallPromptEvent | null>(null);
  const [guide, setGuide] = useState<"ios" | "android" | null>(null);
  const [installed, setInstalled] = useState(false);

  useEffect(() => {
    const standalone = window.matchMedia("(display-mode: standalone)").matches ||
      Boolean((navigator as Navigator & { standalone?: boolean }).standalone);
    setInstalled(standalone);

    const ua = navigator.userAgent;
    if (/iPhone|iPad|iPod/i.test(ua)) setDevice("ios");
    else if (/Android/i.test(ua)) setDevice("android");

    const receivePrompt = (event: Event) => {
      event.preventDefault();
      setInstallPrompt(event as InstallPromptEvent);
    };
    const finishInstall = () => setInstalled(true);
    window.addEventListener("beforeinstallprompt", receivePrompt);
    window.addEventListener("appinstalled", finishInstall);
    return () => {
      window.removeEventListener("beforeinstallprompt", receivePrompt);
      window.removeEventListener("appinstalled", finishInstall);
    };
  }, []);

  if (!device || installed) return null;

  const openInstall = async () => {
    if (device === "ios") {
      setGuide("ios");
      return;
    }
    if (!installPrompt) {
      setGuide("android");
      return;
    }
    await installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    if (choice.outcome === "accepted") setInstalled(true);
    setInstallPrompt(null);
  };

  return (
    <>
      <button type="button" className="app-install-button" onClick={() => void openInstall()}>
        <span className="app-install-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none"><path d="M12 3v11m0 0 4-4m-4 4-4-4M5 15v3.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V15" /></svg>
        </span>
        <span><b>한살매 수업노트 설치</b><small>{device === "ios" ? "아이폰 홈 화면에 추가하기" : "안드로이드 앱으로 간편하게 설치"}</small></span>
        <i aria-hidden="true">›</i>
      </button>

      {guide && (
        <div className="install-guide-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setGuide(null); }}>
          <section className="install-guide" role="dialog" aria-modal="true" aria-labelledby="install-guide-title">
            <header>
              <span className="install-guide-logo" aria-hidden="true">HSN</span>
              <div><small>한살매 수업노트</small><h2 id="install-guide-title">{guide === "ios" ? "아이폰에 설치하기" : "안드로이드에 설치하기"}</h2></div>
              <button type="button" aria-label="설치 안내 닫기" onClick={() => setGuide(null)}>×</button>
            </header>
            {guide === "ios" ? <IosGuide /> : <AndroidGuide />}
            <footer><button type="button" onClick={() => setGuide(null)}>확인했어요</button></footer>
          </section>
        </div>
      )}
    </>
  );
}

function IosGuide() {
  const safari = /Safari/i.test(navigator.userAgent) && !/CriOS|FxiOS|EdgiOS/i.test(navigator.userAgent);
  return <div className="install-guide-body">
    {!safari && <p className="install-browser-notice"><b>먼저 Safari로 열어 주세요</b><span>문자나 카카오톡에서 열었다면 화면의 <strong>···</strong>를 누르고 <strong>Safari로 열기</strong>를 선택해 주세요.</span></p>}
    <p className="install-guide-lead">아래 순서대로 누르면 홈 화면에 아이콘이 생깁니다.</p>
    <ol className="install-steps">
      <li><em>1</em><span><b>아래쪽 공유 버튼을 눌러 주세요</b><small>네모 위로 화살표가 올라가는 모양입니다.</small></span><i className="share-symbol" aria-label="공유 아이콘">↥</i></li>
      <li><em>2</em><span><b>메뉴를 위로 올려 주세요</b><small>아래쪽 메뉴가 더 보이도록 손가락으로 밀어 올립니다.</small></span><i className="swipe-symbol" aria-hidden="true">↑</i></li>
      <li><em>3</em><span><b>‘홈 화면에 추가’를 눌러 주세요</b><small>＋ 표시가 있는 메뉴를 선택합니다.</small></span><i className="home-add-symbol" aria-hidden="true">＋</i></li>
      <li><em>4</em><span><b>오른쪽 위 ‘추가’를 눌러 주세요</b><small>설치가 끝나면 홈 화면의 한살매 아이콘으로 접속하세요.</small></span><i className="done-symbol" aria-hidden="true">✓</i></li>
    </ol>
    <p className="install-safe-note">App Store 검색은 필요 없으며, 기존 학생 정보와 로그인 정보는 그대로 유지됩니다.</p>
  </div>;
}

function AndroidGuide() {
  return <div className="install-guide-body">
    <p className="install-browser-notice"><b>Chrome에서 열어 주세요</b><span>오른쪽 위 <strong>⋮</strong>를 누른 뒤 <strong>앱 설치</strong> 또는 <strong>홈 화면에 추가</strong>를 선택해 주세요.</span></p>
    <ol className="install-steps android">
      <li><em>1</em><span><b>Chrome 오른쪽 위 ⋮ 누르기</b><small>브라우저 메뉴를 엽니다.</small></span><i aria-hidden="true">⋮</i></li>
      <li><em>2</em><span><b>‘앱 설치’ 누르기</b><small>확인창에서 설치를 한 번 더 누르면 완료됩니다.</small></span><i className="done-symbol" aria-hidden="true">✓</i></li>
    </ol>
    <p className="install-safe-note">APK 파일을 내려받지 않는 Chrome 공식 설치 방식입니다.</p>
  </div>;
}
