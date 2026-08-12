"use client";

import type { View } from "./page";

export function BulkRegistrationGuide({ onNavigate }: { onNavigate: (view: View) => void }) {
  return <>
    <div className="page-heading compact guide-heading"><div><p className="eyebrow">처음 사용하는 관리자용</p><h1>학생·계정 일괄 등록 설명서</h1><p>학생 명단을 먼저 등록하고, 로그인 계정을 연결하면 됩니다.</p></div><span className="guide-time">약 10분</span></div>
    <section className="guide-flow" aria-label="일괄 등록 순서"><span className="active"><b>1</b>학생·클래스 등록</span><i>→</i><span><b>2</b>등록 결과 확인</span><i>→</i><span><b>3</b>로그인 계정 생성</span><i>→</i><span><b>4</b>접속 정보 전달</span></section>

    <section className="guide-step-card">
      <div className="guide-copy"><p className="eyebrow">STEP 1</p><h2>학생 명단과 수강 클래스를 먼저 넣어요</h2><p><b>학생 일괄 등록</b>에서 CSV 양식을 내려받아 엑셀로 엽니다. 학생 한 명이 여러 수업을 들으면 학생 정보를 같은 내용으로 여러 줄 작성하세요.</p><ul><li>학생이름은 필수예요.</li><li>클래스를 입력했다면 과목도 입력해요.</li><li>파일은 반드시 <b>CSV UTF-8</b> 형식으로 저장해요.</li></ul><button className="primary" onClick={() => onNavigate("bulk-import")}>학생 일괄 등록 열기</button></div>
      <GuideRosterPicture />
    </section>

    <section className="guide-warning"><span>!</span><div><b>등록 버튼을 누르기 전 미리보기를 확인하세요</b><p>빨간 오류가 있으면 해당 엑셀 행을 고쳐 다시 선택합니다. 오류가 0건일 때만 최종 등록 버튼이 활성화됩니다.</p></div></section>

    <section className="guide-step-card reverse">
      <GuideAccountPicture />
      <div className="guide-copy"><p className="eyebrow">STEP 2</p><h2>학생·학부모·선생님의 로그인 계정을 만들어요</h2><p><b>계정 일괄 생성</b> 양식에서 역할과 연결 정보를 작성합니다. 먼저 등록한 학생 이름과 정확히 같아야 안전하게 연결됩니다.</p><ul><li>학생: <b>연결학생</b>에 본인 이름</li><li>학부모: <b>연결자녀</b>에 자녀 이름</li><li>교사: <b>담당클래스</b>에 클래스 이름</li><li>여러 명이나 여러 클래스는 <b>|</b> 기호로 구분</li></ul><button className="primary" onClick={() => onNavigate("bulk-accounts")}>계정 일괄 생성 열기</button></div>
    </section>

    <section className="guide-finish"><div><span>✓</span><h2>마지막으로 접속 정보 파일을 안전하게 전달하세요</h2><p>계정 생성이 끝나면 이메일과 임시 비밀번호가 담긴 CSV를 한 번 내려받습니다. 각 사용자에게 본인의 정보만 개별 전달하고, 첫 로그인 후 비밀번호 변경을 안내하세요.</p></div><ol><li><b>1</b>생성 결과 CSV 다운로드</li><li><b>2</b>개인별 접속 정보 전달</li><li><b>3</b>로그인·역할 화면 확인</li></ol></section>
  </>;
}

function GuideRosterPicture() {
  return <figure className="guide-picture"><figcaption><i /><i /><i /><span>학생·클래스 일괄 등록</span></figcaption><div className="guide-sheet"><header><b>학생이름</b><b>학교</b><b>학년</b><b>클래스</b><b>과목</b></header><p><strong>김민준</strong><span>배곧중</span><span>중2</span><em>중2 수학 A</em><span>수학</span></p><p><strong>김민준</strong><span>배곧중</span><span>중2</span><em>중2 영어 B</em><span>영어</span></p><p><strong>이서윤</strong><span>서해고</span><span>고1</span><em>고1 국어</em><span>국어</span></p></div><div className="guide-picture-status"><span>✓ 오류 없음</span><b>검증한 내용 등록</b></div></figure>;
}

function GuideAccountPicture() {
  return <figure className="guide-picture accounts"><figcaption><i /><i /><i /><span>로그인 계정 일괄 생성</span></figcaption><div className="guide-account-list"><p><i>학</i><span><b>김민준</b><small>student@example.com</small></span><em>학생 · 김민준 연결</em></p><p><i>부</i><span><b>김보호</b><small>parent@example.com</small></span><em>학부모 · 김민준 연결</em></p><p><i>교</i><span><b>박선생</b><small>teacher@example.com</small></span><em>교사 · 중2 수학 A</em></p></div><div className="guide-picture-status"><span>3개 계정 준비 완료</span><b>계정 생성</b></div></figure>;
}
