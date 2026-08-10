# 한살매 학생관리 앱 — PowerShell 시작

## 1. 필요한 프로그램 확인

```powershell
node --version
npm --version
git --version
```

## 2. 프로젝트 실행

프로젝트 폴더에서 아래 명령을 실행합니다.

```powershell
npm install
npm run dev
```

화면에 표시되는 로컬 주소를 브라우저에서 엽니다.

## 3. Supabase 새 프로젝트 준비

1. 보카 앱과 다른 새 Supabase 프로젝트를 만듭니다.
2. SQL Editor에서 `supabase/migrations/001_initial_schema.sql` 내용을 실행합니다.
3. Project Settings의 URL과 anon key를 확인합니다.
4. `.env.example`을 `.env.local`로 복사하고 값을 입력합니다.

```powershell
Copy-Item .env.example .env.local
notepad .env.local
```

`service_role` 키와 알리고 비밀키는 브라우저용 환경변수에 넣거나 GitHub에 커밋하지 않습니다.

## 4. GitHub 저장소 연결

새 빈 GitHub 저장소를 만든 후 주소를 넣습니다.

```powershell
git add .
git commit -m "한살매 학생관리 앱 초기 화면"
git remote add origin https://github.com/YOUR_ID/YOUR_REPOSITORY.git
git branch -M main
git push -u origin main
```

이미 `origin`이 있다면 `git remote add origin`은 실행하지 않습니다.

## 현재 단계

- 한살매 브랜드 선생님 대시보드
- 학생 목록과 다과목 표시
- 주간 시간표 화면
- 출결·과제·상담 메뉴 골격
- Supabase 관계형 초기 스키마

다음 단계에서 Supabase 로그인, 실제 학생 등록, 클래스 등록, 시간표 저장을 연결합니다.
