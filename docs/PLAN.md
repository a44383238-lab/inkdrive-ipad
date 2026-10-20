# InkDrive pre-build implementation plan

**Goal:** 전체 앱 소스와 로컬 검증을 준비하되 IPA 생성과 외부 업로드는 실행하지 않는다.

**Architecture:** Expo 56 library shell; local Expo module presents a native PDF editor. Swift handles all Pencil input, page editing, PDF appearance persistence, security-scoped file coordination, and close/save sequencing.

**Constraints:** iPadOS 17+, Pencil 2 baseline; source mirror read-only; no signing details invented; no GitHub/EAS/IPA operation.

1. Write behavior tests for validation, library ordering, operation exclusion; implement and run on Node.
2. Write native tests for PDF round trip, rotated/cropped pages, external annotation preservation, page operations, conflict-safe disk writes. Implement native persistence/session. Apple tests cannot run on this Windows host; record as pending, never as passed.
3. Implement Pencil canvas, global undo, custom lasso and edit menus, text/shape tools, page drawer, movable toolbar, Pencil double tap, two-finger double tap.
4. Connect system folder/PDF pickers and native editor to an Expo library with search, create folder/note, recent documents, settings/presets.
5. Install locked JS dependencies, run tests/typecheck/Expo configuration/autolinking checks. Inspect source with a separate reviewer. Produce an exact status report including native verification gaps.

Review focus: save-while-editing; close during pending saves; cropped/rotated coordinates; remote modifications; invalid names/bookmarks; canceled pickers; annotation duplication; last-page deletion; backgrounding.
