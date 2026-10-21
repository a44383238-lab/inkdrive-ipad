# InkDrive 2.0 — 소스 감사와 실행 설계

작성: 2026-10-21 (한국 시간). 기준: main / affe50e. 요청 지시서의 Phase 0–8은 최종 목표이며 이 문서는 완료 보고가 아니다. Phase의 성공 기준을 만족하면 추가 승인 없이 다음 작업으로 진행한다. GitHub Actions, macOS 빌드 및 IPA 생성은 별도 명시 요청 전까지 실행하지 않는다.

## 1. 현재 실제 상태와 검증

| 영역 | 실제 코드 | 판단 |
|---|---|---|
| iPad 앱 | native/Sources, native/project.yml | 독립 SwiftUI/UIKit. Xcode 대상에 Expo/React가 포함되지 않는다. 루트 npm 버전 0.3은 이전 호스트 버전이며 실제 native 앱은 0.4.0(4)이다. |
| PDF/펜슬 | PDFModel, PageOverlay, EditorSession | PDFKit 위 PKCanvasView, Pencil 전용 입력, 손가락 스크롤/확대. UndoManager와 지연 저장을 재사용한다. |
| 기존 필기 저장 | InkAnnotation | PKDrawing 원본은 PDF 사용자 정의 키에 base64로 보존한다. 외부 뷰어 표시용 appearance는 drawing.image(scale≤2, 면적≤1600만 픽셀)를 사용한다. 편집 원본까지 저해상도라는 뜻은 아니며 저장 PDF 외관 확대 시 화질 한계의 직접 원인이다. |
| 문서 식별 | PDFModel | 페이지 UUID는 숨김 주석으로 보존한다. 공통 document UUID/독립 ink revision은 없다. 동일 파일에 중복 페이지 ID가 있으면 새 규격 수입 단계에서 거부·복구해야 한다. |
| 저장 안정성 | CoordinatedStore, EditorSession | NSFileCoordinator, 읽을 때/쓸 때 unresolved conflict 검사, 예상 SHA256 비교, 단일 파일 atomic 쓰기, 저장 중 추가 편집 처리, 충돌 시 자동 덮어쓰기 차단. 별도 영구 필기 journal/다중 파일 commit은 아직 없다. |
| 서재 | LibraryRepository, NativeLibraryStore | 사용자 지정 iCloud 폴더 security bookmark, 루트 탈출 방지. 현재 서재 파일 필터는 pdf/md/txt만 허용한다. PPTX/HTML 등을 이미 열 수 있다고 보고하면 안 된다. |
| 녹음 | RecordingService, PendingRecording, RecordingBrowser | AAC/M4A 기기 로컬 선저장, pending 복구, 종료 후 iCloud 복사 및 해시 확인, PDF/날짜 연결, 재생·탐색·배속. iPad 실제 마이크와 장시간 중단 복구는 별도 검증 필요. |
| Windows AI | desktop-control/runner, daily-handoff, transcribe | 127.0.0.1 수동 창, 수동·야간 같은 실행기, 원본 해시와 수업 종료 검증, 중복 작업 잠금, 로컬 Whisper, ChatGPT 로그인 CLI로 노트/문제 작성. native Windows 서재/필기 뷰어는 아직 없다. |
| 학교 연동 | docs/CAMPUS-SYNC.md, work/campus-probe의 실험 | 2026-10-20 인증된 별도 HTTP 클라이언트에서 시간표 JSON, Moodle AJAX 수강목록, 과제 상세, 492490바이트 원본 PDF 수신 성공. 학교 세션 영구 유지·요청 본문 생성·스케줄러·제품 버튼은 미구현이다. |
| 기존 검사 | npm test (이번 실행) | 총21, 통과20, 실패0, skip1. skip은 INKDRIVE_TEST_PYTHON/FFMPEG 미설정으로 빠진 faster-whisper 배치 worker 검사이다. |
| Swift 검사 | STATUS.md에 남은 이전 run 39434333188 | 과거 Swift 28개 + 앱 UI 시나리오 1개 기록. 이번 Windows 환경에서 재실행한 결과가 아니며 실제 iPad Pro/Pencil 검증을 대신하지 않는다. |

현재 작업 트리에는 별도 작업의 transcribe 변경과 faster-whisper 신규 파일이 있다. 이 변경은 보존하며 이번 벡터 작업에 섞어 커밋/되돌리기하지 않는다. sources/는 읽기 전용이다. 현재 Windows에는 Node와 .NET runtime이 있지만 `dotnet --list-sdks`에서 SDK는 확인되지 않았다. Swift/Xcode도 없어 native 변경 검사는 추후 허가된 환경에서 해야 한다.

운영 상태를 추가 확인했을 때 기존 22시 AI 예약(22)과 GPT 학교 확인 예약(plato)은 모두 PAUSED였다. 구현된 실행기와 실제 활성 예약을 구분한다. 이번 작업에서 이 상태를 변경하지 않았다. 또한 quickLesson은 PDF의 바로 위 폴더명을 subject로 사용하므로, 향후 `과목/강의자료/파일` 구조에서는 과목을 잘못 판단할 수 있다. Phase 5/7에서 과목 ID 기반 연결을 추가하고 기존 경로 필드를 호환 유지해야 한다.

## 2. 재사용할 부분

PDFKit 문서 표시/페이지 조작, PencilKit 입력·원본 drawing, EditorSession의 undo/dirty/save-loop, NSFileCoordinator 및 예상 해시 충돌 검사, 녹음/복구/재생, 폴더 UI/탭/도구 설정, Node AI 실행기와 원본 해시 인계 방식을 유지한다. 기존 PDF의 외부 주석은 보존한다. 기존 iCloud 자료는 자동 이동하거나 일괄 변환하지 않는다.

## 3. 새로 만들거나 분리할 부분

- DocumentAdapter(PDF/PPTX/HTML/image): 페이지 ID·좌표·표시·원본 fingerprint 제공.
- Ink Engine: PencilKit 입력을 유지하되 변경 획과 독립 sidecar 저장을 분리.
- 공통 geometry와 renderer: JSON 검증·좌표 변환·압력/굵기·색상/투명도 재현.
- NativeInkArchive: 편집 충실도를 위해 PKDrawing 원본을 별도 보존. 공통 JSON이 PKDrawing 바이너리를 대체하지 않는다.
- PDFExporter: 원문을 rasterize하지 않고 앱 소유 벡터 appearance만 갱신. 독립 잉크 저장 성공과 PDF export 성공을 별도 상태로 표시.
- DocumentRegistry/SyncManager: 파일명과 분리된 UUID, 버전·부분 수신·충돌 관리.
- CampusClient/SyncCoordinator: 학교 세션 직접 HTTP, 증분 수집, 수동/주기 같은 실행기.
- Windows read-only shell/viewer: 초기부터 읽기 전용. 전사 프로그램은 별도 모듈로 재사용.

## 4. InkDrive Ink Format v1 초안

기계 규격은 shared/ink-format.schema.json, 참조 구현은 shared/ink-format.mjs이다. JSON 문서의 version=1, format=inkdrive.ink, documentId(UUID), sourceRevision(SHA256), inkRevision(양의 정수), parentRevision(선택), createdAt/updatedAt(UTC ISO), layers, pages를 둔다. 페이지는 stable id, kind, bounds, rotation과 획을 가진다. 획은 UUID, layerId, tool, color(#RRGGBB), opacity, 생성/수정 시각, affine transform, samples와 보존용 native 참조(선택)를 가진다. samples는 문서 좌표 x/y, 실제 size width/height, pressure, opacity, 획 시작 후 timeMs를 담는다.

PDF 좌표는 cropBox의 실제 bottom-left user-space(pt), PPTX는 원래 슬라이드 EMU, HTML snapshot은 고정 CSS px, 이미지는 원본 px를 쓴다. 화면 배율·DPR은 저장하지 않는다. rotation은 원점/크기를 포함한 명시적 행렬로 적용한다. 페이지 순서는 배열 표시 순서이고 ID가 필기 연결 기준이다. exporter는 stroke transform을 한 번만 적용하고 점의 size에 pressure를 또 곱하지 않는다(PencilKit size에 이미 반영될 수 있다).

v1 참조 renderer는 부드러운 가변 굵기 벡터 면을 만든다. PencilKit 연필의 종이 질감/특수 nib·부분 지우개 mask를 완전히 동일하게 재현했다고 주장하지 않는다. native archive와 mask/outline 확장 정보를 보존하고, 정확한 추출이 안 되는 획은 조용히 잘못 변환하지 말고 기존 표시/원본 보존 경로로 남긴다. 시간 정보는 획 상대 시각과 절대 생성 시각을 함께 유지해 향후 녹음 연결에 사용한다.

## 5. 두 앱의 데이터 흐름

학교 로그인(webview 전용 profile) → 서비스별 인증된 HTTP → 원본 파일 임시 수신 → 크기/형식/해시 검증 → 새 source revision 등록 → 공통 서재.

iPad PencilKit 입력 → 로컬 복구 journal/PKDrawing archive → 공통 ink JSON → 버전 commit → iCloud.

Windows 로컬 index → 마지막 검증된 commit + 일치하는 source/ink → 문서 renderer + 벡터 overlay → 읽기 전용 표시.

수업 lesson ID는 과목/시간, 자료 documentId+revision, ink revision, 녹음 ID와 AI 결과를 묶는다. 현재 LessonRecord.pdf 경로와 원본 SHA는 과도기 호환 필드로 유지하고 기존 daily-handoff를 깨지 않는다.

## 6. iCloud 저장/동기화

사용자가 보는 `학기/과목/파일` 경로는 유지하고 관리 정보는 `.inkdrive/documents/<uuid>/`로 분리한다. UUID를 파일명에서 만들지 않는다. 외부 PDF 이동은 (a) 문서에 보존 가능한 소유 document ID, (b) 로컬 file identity, (c) 이전 source hash로 복구하며 모호하면 별도 문서로 보존한다. 동일한 빈 PDF 파일 두 개를 해시만으로 하나의 문서로 합치지 않는다.

commit은 불변 파일이며 document/source/ink/native 파일의 SHA, byte count, parent commit, device ID, 생성 시각을 포함한다. 내용 파일을 먼저 쓰고 commit을 마지막에 쓴다. 이것은 iCloud 도착 순서를 보장하지 않는다. 수신기는 참조 파일의 전체 해시/길이를 확인한 commit만 사용하고 미완성 새 commit은 대기시킨다. 이전 검증본을 기기 로컬 cache에서 계속 표시한다. 같은 parent에서 갈라진 다른 commit을 발견하면 양쪽을 보존하고 충돌로 표시한다. 공유 SQLite/WAL을 iCloud에 두지 않는다.

로컬 journal을 먼저 내구성 있게 저장하고, PDF 외부 반영이 실패해도 ink 저장 성공은 잃지 않는다. PDF export는 대상 source hash가 일치할 때만 수행한다. 새 학교 자료는 새 source revision으로 받고 기존 필기 문서 원본을 덮어쓰지 않는다. 자동 GC/원본 삭제는 초기 버전에서 하지 않는다.

기존 v1 PDF에서 이관할 때 원본 bytes 백업 → PKDrawing 해독 → 페이지 ID/annotation count 검증 → 새 sidecar 작성 → reopen 비교 → commit 확인 순서다. 기존 소유 주석 제거는 성공 검증 뒤 export 복제본에서만 한다. 실제 사용자 파일을 시험 재료로 쓰지 않는다.

## 7. PLATO 인증·수집

iPad WKWebsiteDataStore.default의 서비스별 cookie를 URLSession의 domain/path/secure/expiry 규칙에 맞춰 연동하고 새 Set-Cookie도 웹뷰에 반영한다. Windows는 전용 WebView2 profile+CookieManager를 우선 후보로 두며 OS 안전 저장소를 쓴다. Safari/외부 브라우저와 앱이 자동으로 cookie를 공유한다고 가정하지 않는다. 기기 간 토큰을 iCloud로 운반하지 않는다.

MoodleSession+sesskey AJAX 수강목록에서 shortname의 학년도·학기/과목 코드/분반을 학지시와 대응한다. ubfile/과제는 커스텀 모듈이므로 필요한 목록·상세 HTML 파서를 보완한다. 학지시에는 CSRF뿐 아니라 요청 본문 암호화가 있어 관측 요청을 단순 replay하는 실험에서 독립 요청 생성으로 전환해야 한다. 학교가 요구하는 이메일 2차 인증/비밀번호 갱신은 사용자에게 넘기고 우회하지 않는다.

증분 식별키는 school/term/courseId/resourceId/attachmentId. 변경 정보가 있으면 비교하고 파일 bytes는 SHA로 확인한다. 조건부 요청(ETag/Last-Modified)은 서버가 실제 지원할 때만 쓴다. 식별자는 같고 수정 메타데이터도 없으면 목록 조회만으로 내용 변경을 알 수 없으므로 제한을 표시하고 과도한 전체 재다운로드를 피한다. 원격 삭제는 local tombstone 표시만 하며 사용자 파일은 삭제하지 않는다. 수동·실행 직후·재연결·30분 timer는 같은 coalesced task를 사용한다. 수업 전후 5분 확인은 기본 해제하고 정책/부하 검증 뒤 적용한다. 배터리 절약은 60분, 오프라인은 backoff 후 연결 복구 시 즉시 검사한다. iPad background 정확한 주기는 보장하지 않는다. Windows가 꺼져도 활성 iPad는 직접 요청한다. GPT는 이 수집 엔진에 들어가지 않는다.

로그인됨 / 자료 내려받음 / 로컬 저장됨 / iCloud 전달 대기는 각각 별개다. 대기 항목을 수집 완료로 표시하지 않는다. GPT heartbeat plato는 사용자 결정으로 PAUSED이며 새 직접 실행기를 대신해 재활성화하지 않는다.

## 8. 기술 선택과 제약

Windows는 C#+WPF/WebView2 또는 WinUI3를 우선 검토한다. WPF는 기존 Node worker 연동과 일반 exe 설치가 단순하며 WebView2 cookie API를 사용 가능하다. WinUI3는 현대 UI지만 SDK/MSIX/배포 종속성이 늘어난다. Electron은 JS 공통 renderer 재사용이 쉽지만 배포 크기와 RAM 비용이 있다. 로컬 .NET SDK가 없으므로 설치 없는 공통 SVG/HTML 참조 뷰어로 좌표 검증을 먼저 수행하고, 정식 shell 선정은 작동 검증 뒤 확정한다. 참조 뷰어를 완성된 Windows 앱이라고 부르지 않는다.

이후 기존 .NET Framework C# compiler/WPF가 사용 가능함을 확인했다. 별도 SDK 설치 없이 WPF+WebView2의 Windows 실행 검증본을 만들고 실제 창에서 100%/400% 표시를 확인했다. 외부 `http://127.0.0.1:8770` 검증 서버를 독립 Node 프로세스로 실행한다. 배포본은 기존 설치된 Node.js, .NET Framework 4.8, Edge WebView2 Runtime에 의존한다. 전체 서재 관리 앱이 아닌 합성 문서 전용 read-only prototype이며, 정식 Windows 대상으로는 유지보수 가능한 현재 .NET SDK 프로젝트로 전환을 검토한다. 이 검증본은 macOS/iPad/IPA 빌드와 관계없다.

PPTX의 완전한 충실도는 폰트/차트/수식/SmartArt와 렌더러 라이선스 문제다. 원본은 유지하고 Windows PowerPoint COM이 사용 가능할 때 슬라이드별 고품질 preview와 EMU 크기/관계 ID를 추출하는 경로를 우선한다. iPad 오프라인 대체는 파일과 함께 동기화된 preview, 없으면 QuickLook 원본 열람(정확한 ink overlay는 보장 못함)으로 나눠 표시한다. 모든 PPTX를 PDF로 강제 변환하지 않는다. 원본 수정 시 slideId/relationship+content fingerprint 비교로 기존 ink를 이전 revision에 보존한다.

HTML은 sandboxed 웹 보기(학습 자료의 코드가 앱 bridge/인증 저장소를 호출하지 못하게 분리)와 고정 폭 snapshot 필기 보기를 구분한다. 문서 reflow 뒤 임의로 같은 좌표에 기존 ink를 씌우지 않는다. HWP/HWPX/DOCX/ZIP은 수집과 보관 가능 여부와 native 열람 가능 여부를 구분한다.

PKDrawing→공통 벡터 추출 시 pressure/transform/mask/nib, PDF crop/rotation, native renderer 유사성, 100페이지 lazy loading이 가장 큰 위험이다. 공통 format 자체의 성공은 실제 Pencil 성능과 동일하지 않다.

## 9. Phase 의존관계와 진행 기준

| Phase | 산출물 | 다음으로 진행할 기준 |
|---|---|---|
| 0 | 소스 감사/현황/설계/테스트 기준 | 실제 코드 대조와 기준 테스트 기록 |
| 1 | JSON 규격/validator/좌표·vector renderer/참조 뷰어 | schema round-trip, 변환/회전·획 ID, 100–400% 벡터, 잘못된 데이터 거부. 실제 PKDrawing 추출은 별도 native 판정 |
| 2 | PKDrawing exporter+독립 local journal+source compatibility | native tests, mask·undo·erase·압력·저장 실패·재실행 검증. 빌드 허가 없는 현재 환경에서는 native 검증 대기 표시 |
| 3 | Windows read-only shell+PDF overlay | 실제 PDF 선택·zoom·page ID·색/굵기·원본 비수정 검증 |
| 4 | 불변 commit·registry·local cache | 부분 도착, 해시불일치, 파일명 변경, fork conflict, offline round-trip 검증 |
| 5 | 양쪽 PLATO 탭/직접 수집/수동·자동 | 실제 profile 로그인·만료·신규/동일/수정/삭제, 중복실행·offline·학기전환 검증 |
| 6 | PPTX preview/HTML 두 모드/adapters | 4:3/16:9/사용자비율, slide ID 이동, HTML 폭 변경·원본 보존 |
| 7 | Windows AI/녹음/상태 통합 | 기존 20개 회귀+실제 합성 인계, 취소·재개·원본 hash 불변 |
| 8 | 성능/실기기/iCloud 안정화 | 실제 iPad Pencil+마이크, 양기기 offline/동시변경, 100+페이지, 사용자 acceptance |

모든 항목을 이번에 완료했다고 처리하지 않는다. 독립적으로 검증 가능한 작업은 병행 진행하되 의존성이 검증되지 않은 Phase를 완료 처리하지 않는다.

## 10. 테스트와 성공 판정

- PNG 비교만으로 벡터라고 판정하지 않는다. SVG에 bitmap이 없는지, PDF export에서 image XObject 대신 vector path가 쓰였는지 함께 검사한다.
- crop origin≠0, rotation 0/90/180/270, point↔display 왕복, DPI/화면 확대 독립성, 좌표·sample opacity·force·size 보존, 순서 변경 뒤 ID 연결.
- native PKDrawing 원본 bytes와 개별 획 수, 지우개 mask, 올가미 transform, undo/redo 후 저장/재실행.
- 새 source revision+inkRevision 불일치 거부, 손상/부분 파일 새 commit 대기, 이전 정상본 유지, 동시편집 fork 보존.
- reference viewer 100/200/400% 확대, PDF와 overlay 동일 matrix, 100페이지 lazy fetch와 page cache 제한. 합성 fixture와 실자료 검증을 분리한다.
- 로그인 상태/로컬 다운로드/iCloud 도착을 혼동하지 않는 상태 검증, cookie/세션이 로그/프로젝트/iCloud에 남지 않는 검증.
- 학교 자료 파일명 충돌·path traversal·HTML 로그인 오류·중단 다운로드·재시도·수정본과 필기 원본 분리.

## 출처와 범위

직접 근거: 위 실제 소스 파일, 이번 npm test, work/campus-probe/direct-api-evidence.json. 이전 build는 docs/STATUS.md에 기록된 역사 자료다.

플랫폼 참고: [Apple PKStrokePath interpolation](https://developer.apple.com/documentation/pencilkit/pkstrokepath-swift.struct/interpolatedpoint(at:)), [Apple PKStroke mask](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct/mask-16kkz), [Microsoft WebView2 CookieManagement](https://github.com/MicrosoftEdge/WebView2Feedback/blob/main/specs/CookieManagement.md). 이 문서들은 해당 플랫폼 기능의 근거이며 InkDrive에서 그 기능의 검증이 끝났다는 증거는 아니다.

## 이번 진행 결과 (2026-10-21)

| 범위 | 실제 결과 | 아직 충족하지 않은 기준 |
|---|---|---|
| Phase 0 | 본 감사·설계서와 아래 실행 기준 작성 완료 | 최신 기기 문제 재현은 별도 |
| Phase 1 | JSON Schema, 공통 validator, crop/rotation matrix, 가변 굵기 벡터 경로, 읽기 전용 참조 renderer 구현·검증 | 실제 iPad PKDrawing 추출본과 Windows 비교, 질감/부분 지우개 mask의 동일 표시 |
| Phase 2 착수 | PortableInk.swift와 PortableInkTests.swift(2개) 작성. stroke ID는 호출자가 제공하고 mask는 명시적으로 거부해 지운 획이 되살아나지 않게 설계 | Swift 컴파일/실행 미검증. 기존 저장 경로에 연결하지 않았으며 iPad 앱의 기존 bitmap appearance는 아직 바뀌지 않았다. 로컬 journal/일괄 이전 미구현 |
| Phase 3 독립 검증 | WPF Windows 실행 파일 + PDF.js 배경 + SVG overlay 실행. 합성 100페이지, 원본 해시 검증, 페이지 이동, zoom 확인 | 실제 iCloud 서재/실제 iPad 필기/과목/AI UI의 제품 통합은 아직 |
| Phase 4 기초 | shared/ink-commits.mjs의 내용 주소 기반 불변 저장/검증/부분 수신/충돌 분기 테스트 통과 | 실제 iCloud 전달·기기 로컬 cache·rename registry·Swift 저장소 통합은 아직 |
| Phase 5–8 | 설계/의존관계/기존 학교 직접 HTTP 실험 정리 | 지속 수집 제품, PPTX/HTML, 최종 AI UI 통합 및 실기기 종합 검증 미구현 |

전체 `npm test`: **31 pass / 0 fail / 0 skipped**. 기존 faster-whisper 회귀는 실제 설치된 Python/FFmpeg 경로를 이번 테스트 프로세스에만 지정해 재실행했고, inference는 해당 테스트의 가짜 모델을 사용했다. 수업 원음은 재생하거나 전사하지 않았다. 신규 항목은 ink format 5, immutable commit 4, reference viewer 1이다. 이 숫자에 실행하지 않은 Swift 테스트는 포함하지 않는다.

화면 검사는 합성 PDF의 1·2·3·4·100페이지와 100·200·400% 조합 15개에서 PDF.js viewport matrix와 SVG page matrix×zoom의 일치를 확인했다. SVG 내부 image는 0개, vector path는 3개였다. Windows native 창에서도 400% 상태 표시와 렌더링을 확인했다. 100페이지 탐색이 된 사실을 긴 실제 수업 자료의 성능 최적화가 완료됐다는 주장으로 확대하지 않는다.

임시 테스트 디렉터리 외 사용자 iCloud 문서·녹음은 수정하지 않았다. GitHub Actions/macOS 빌드/IPA 생성/푸시는 실행하지 않았다. 아직 기존 iPad 필기 화질이 개선된 설치본은 없다. 네이티브 검증이라는 의존성이 해결되기 전에는 Phase 2 및 전체 Phase를 완료 처리하지 않는다.
