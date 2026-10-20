# InkDrive 0.4 — standalone Swift app

The iPad application target is now entirely Swift: SwiftUI library and UIKit/PDFKit/PencilKit editor. It does not contain Expo, React, Hermes or a development launcher. The Windows lecture-processing helper remains a separate tool.

## Current verification

- GitHub repository changed to public at the user's explicit request. Standard macOS jobs now start successfully.
- Standalone arm64 Debug app compiled successfully in run 39429521012, source 512a601.
- Core/editor/recording-browser regression tests passed in that run. Actual app interaction testing is in progress.
- Later reference-video refinements (lasso handles/popover, text styles, toolbar boundary and explicit scene metadata) are being validated in the next native build.
- Hardware Pencil input, microphone capture, Sideloadly installation and iCloud synchronization with Windows still need device validation.

## App flow

1. Sign/install the Swift IPA with Sideloadly using the existing bundle identifier. Do not delete the installed app merely to update it.
2. Select the InkDrive iCloud folder as the library root.
3. Open a PDF and use the single microphone button to start/stop recording. The app chooses the PDF/date association automatically.
4. The recording-list icon opens all saved recordings for the current PDF. Selecting a recording plays it; the list itself never autoplays. Seek, skip 10 seconds and choose 0.5–2× speed.
5. Mark the class ended in the class screen. The existing notebook automation/manual button handles transcription, detailed notes and review questions.

## Reference functions

Folder icon grid; hard library root; compact icon tools; per-tool color/width(px)/opacity; presets; toolbar positioning; Pencil writing/finger pan; Pencil 2 double-tap; two-finger undo; erasers; lasso copy/cut/paste/delete/color/width/size/rotation; text font/size/color/alignment/styles; recent document tabs; page thumbnails, add/delete/reorder, outline, bookmarks, search and page-number jump.

See STATUS-0.2-history.md for historical Expo-era checks. Those Metro/launcher instructions do not apply to the standalone Swift application.
