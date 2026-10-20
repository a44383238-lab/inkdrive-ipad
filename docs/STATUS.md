# InkDrive 0.4 — standalone Swift app

The iPad application target is now entirely Swift: SwiftUI library and UIKit/PDFKit/PencilKit editor. It does not contain Expo, React, Hermes or a development launcher. The Windows lecture-processing helper remains a separate tool.

## Current verification

- Public repository confirmed. Standard macOS jobs run without the prior private-repository billing block.
- Final native run **39434333188**, app source **8caa91131c2a40a244b06049b0ff78284274a53a**, succeeded on standard macos-15 / Xcode16.4. iPadOS18.5 simulator.
- Physical iPad arm64 Debug app compilation and packaging passed.
- **28 Swift core/editor/storage/recording-browser tests passed**, plus **one real app interaction scenario** covering library folder navigation, editor opening, recording browser, page navigator, document tabs and return to the library.
- IPA SHA256: `30406d932bf5c18c87049eb30ed63e4f18b8333a73b7cdd9f59bd919c80af8f0`; 856064 bytes. ZIP CRC, native class symbols, arm64 Mach-O, bundle identifier and iPad support verified. No Expo/React/Hermes/development launcher is packaged.
- App 0.4.0 (4), minimum iOS17, bundle identifier `app.inkdrive.notes`, unsigned for Sideloadly.
- macos-15 is now the default CI image after macos-26 simulator boot migration stalled. Runtime selection matches the active Xcode SDK. This is a CI environment choice, not a reduced deployment target.
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
