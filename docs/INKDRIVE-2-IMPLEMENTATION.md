# InkDrive 0.5 통합 구현 / 검증 기록

2026-10-21 사용자가 남은 Phase 구현 후 IPA 빌드를 명시적으로 요청했다. 개발용 IPA는 기존 app.inkdrive.notes 식별자로 한 번에 갱신한다. 앱 삭제나 실제 수업 자료 일괄 이전은 하지 않는다.

## 연결한 구현

- Phase 2: PDF 외관을 bitmap 대신 가변 굵기 벡터 경로로 저장. 원래 PKDrawing은 그대로 보존한다. 지우개 clip과 올가미 transform을 공통 JSON에 반영한다. 연필 질감과 가변 opacity의 플랫폼 간 외관은 근사이며 동일 픽셀을 보장하지 않는다. 페이지 UUID, 문서 UUID, 페이지로 구분한 획 UUID를 유지한다.
- Phase 2/4: 기기 로컬 복구 journal → 기존 PDF CAS 저장 → 불변 source/ink/native 객체와 commit. 처음 여는 PDF bytes도 별도 originals에 보관한다. 충돌한 journal은 별도 보존한다. commit 전체 참조 파일을 검증하며 부분 도착은 대기, 다중 head는 충돌 처리한다. 기존 PDF의 표준 외관과 편집용 원본을 모두 유지한다.
- Phase 3/4: WPF + WebView2 Windows 앱에 실제 폴더 연결, 서재/오늘 수업/녹음 재생, PDF.js 배경과 공통 SVG 필기, 100/200/400% 확대, rename 후 file SHA 연결, 기기 로컬 정상본 cache를 연결했다. Windows는 읽기 전용이다. Node.js/.NET4.8/WebView2 Runtime에 의존한다.
- Phase 5: iPad WKWebView, Windows 전용 WebView2 profile 로그인과 직접 HTTP 수집기를 연결했다. 비밀번호는 저장하지 않는다. Windows의 cookie는 익명 pipe로 전달하고 파일/프로세스 인자에 넣지 않는다. 학교 외부 redirect를 차단한다. 원본 다운로드, 파일별 해시/학기/과목/자료 ID, 새 버전 별도 보관, per-device 상태, 수동 확인, 활성 iPad 30분/절전60분, 실행 중 Windows30분, 재연결 확인을 구현했다. 수정 정보가 없는 같은 자료는 하루에 한 번 다시 해시를 검사하고 수동 확인은 즉시 검사한다. iOS가 종료된 상태의 정시 실행은 약속하지 않는다.
- 학지시: 공개 gfn_ajax 형식에 맞춰 현재 페이지의 RSA 공개키/CSRF와 메뉴 AUTH_STR로 요청을 새로 만드는 Swift/Node 구현을 추가했다. 단위 테스트는 RSA envelope와 로그인 실패를 검증한다. 실제 학교 세션으로 독립 요청 생성 및 매개변수를 다시 검증해야 한다. 인증된 /main 시간표 HTML 읽기를 보조 경로로 유지한다.
- Phase 6: 파일 형식 제한을 풀고 iPad QuickLook으로 원본을 열람한다. HTML은 학교 로그인과 분리한 임시 WebKit 저장소에서 script를 차단하고 열며 고정 PDF snapshot을 별도로 만든다. 18000px를 넘는 HTML은 잘라 저장하지 않고 거부한다. PPTX는 Windows PowerPoint 읽기 전용/매크로 차단으로 고품질 PDF preview를 만들며 원본 PPTX를 유지한다. 원래 슬라이드 EMU, slide ID, relationship, stable UUID를 저장한다. 미리보기가 iCloud에 도착하면 iPad가 별도 notebook PDF를 편집하며, 공통 ink는 원래 EMU/HTML CSS px로 변환한다. 원본/preview SHA를 분리해 검사한다.
- Phase 7: 기존 녹음/Whisper/ChatGPT 로그인 CLI 파이프라인을 유지한다. lesson에 과목/문서 ID와 녹음 시작 시각을 추가해 job에 인계한다. Windows 수업 정리 버튼, 실행 상태, 22시 시작을 연결한다. 앱/노트북이 켜져 있어야 하며 수동 재실행은 최근 미처리 수업을 검사한다. 기존 PAUSED Codex 예약을 변경하지 않는다.

## 완료 판정과 남은 확인

로컬 JavaScript 회귀: 39 pass, 0 fail, 0 skipped. 파일 보존, 신규/동일/수정 자료, 학기 전환, 인증 만료, 외부 redirect/cookie 격리, RSA 재생성, native 호환 commit, rename/cache를 합성 입력으로 확인했다. 실제 학교 신규 업로드나 실기기 녹음 검증으로 확대 해석하지 않는다.

Swift 신규 exporter, journal/commit, adapter, 학교 parser 테스트 및 앱 UI 회귀는 승인된 macOS CI에서 실행한다. Windows 실행 화면, PowerPoint 4:3/16:9/custom 비율과 원본 해시, native 출력과 공통 renderer의 대조 결과를 빌드 후 기록한다.

Phase 8의 실제 Apple Pencil 압력/지우개/손가락 이동, 마이크 권한/백그라운드 녹음, 두 기기 iCloud 부분 도착/오프라인/동시 편집, 새 학기 실제 학교 응답은 사용자의 설치된 iPad가 필요하다. 합성 테스트나 IPA 생성만으로 이 항목들을 완료 처리하지 않는다. 자동 과제 마감은 상세 원문을 저장하며 별도 정규화된 달력 화면은 후속 검증 범위다. HWP/HWPX/ZIP은 수집·보관과 해당 OS의 열람 지원을 구분한다.
