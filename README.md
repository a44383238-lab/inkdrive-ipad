# InkDrive

Standalone iPad PDF notebook written in SwiftUI, UIKit, PDFKit and PencilKit. iPadOS 17+, iPad Pro M2 / Pencil 2 baseline. The 0.4 iPad app needs no JavaScript runtime, Expo account, Metro server, launch URL, or running notebook computer for writing and recording.

## Native app

- `native/Sources/`: SwiftUI library, folders, class summaries, settings and editor presentation.
- `modules/inkdrive/ios/Core/` and `UI/`: reusable Swift file access, PDF editing, Pencil input, recording and playback.
- `native/project.yml`: XcodeGen application and UI test targets.
- `.github/workflows/ios-development.yml`: manually dispatched standard macOS runner; compiles the app, runs core and actual app interaction tests, exports an unsigned arm64 Debug IPA.
- Sign and install the resulting IPA with Sideloadly. The existing bundle identifier `app.inkdrive.notes` is preserved. Apple signing requirements still apply.
- Root React/Expo files describe the earlier 0.1–0.3 host and are retained as development history; they are excluded from the native application target and native build.

On a Mac: install Xcode and XcodeGen, then run `bash scripts/build-native-ios.sh`. GitHub push/build execution follows the user's authorization. The repository was made public at the user's request on 2026-10-20; use standard macOS runners, not paid larger runners.

## Storage and input

Choose an iCloud Drive folder as the library root. Pencil writes; fingers pan and zoom. In-place PDF updates preserve external annotations. Conflicts stop overwrite and preserve the editor for recovery. Library navigation never goes above the selected root.

Start and stop recording from the editor microphone. PDF and date association is automatic. The adjacent recording-list icon opens that PDF's recordings across dates, with playback, seeking, 10-second skips and 0.5–2x speed. Recordings are never deleted by hiding duplicate list entries. Mark a class ended in the class screen so the nightly process can verify its complete inputs.

The reference video also informs movable toolbars, quick pen presets, anchored tool/selection settings, lasso editing, text formatting, document tabs, page thumbnails, outline, bookmarks, search and page-number navigation. Hardware Pencil input, microphone capture and cross-device iCloud synchronization require iPad checks beyond simulator tests.

## Workspace rules

- `../sources/` is read-only reference material.
- No lecture recordings, PDFs, local configuration or credentials belong in Git.
- Windows helper code remains separate from the iPad app. It continues to use the existing ChatGPT subscription and local transcription, without adding a paid AI API.

## Notebook manual button

The Windows desktop shortcut **InkDrive 수업 정리** opens a loopback-only control window. **지금 수업 정리** starts the same pipeline used by the nightly automation, including the previous seven days if selected. `scripts/open-manual.cmd` opens it from a relocated source checkout. It uses the existing ChatGPT-authenticated Codex CLI, strips separate API-key environment variables, and requests the workspace-write sandbox. Closing the browser window does not stop an already running helper process. No startup item or Windows scheduled task is installed.
