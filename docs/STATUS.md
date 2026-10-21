# InkDrive 0.5.0 (5) — verified integrated development build

2026-10-21. Standalone Swift app. No Expo, Metro, development launcher or notebook development server is required to open the iPad app.

## Delivered build

- [Successful build and UI tests](https://github.com/a44383238-lab/inkdrive-ipad/actions/runs/39550880481), source `1b164917540072e75b22b73fc41ddd7d70392446`.
- `InkDrive-Swift-development.ipa`: 1,248,211 bytes; SHA256 `68bb6631d8e3fb1f6ebeb78dd98264ff60ee15ecbdb1831a407736ee7279b169`.
- Version 0.5.0 (5), bundle `app.inkdrive.notes`, minimum iOS17, arm64, unsigned for Sideloadly. ZIP CRC, platform and native modules verified.
- The same verified file is on the Desktop as `InkDrive 개발용.ipa`. The preceding desktop IPA is preserved in outputs as a backup. Update the existing app with Sideloadly; do not delete it merely to update.
- Windows product is `outputs/InkDrive2-Windows/InkDrive.exe`, with its required sibling files. Desktop `InkDrive.lnk` launches that product. Node.js/.NET4.8/WebView2 are required and verified on this PC.

## App flow

1. Select the iCloud InkDrive folder as the library root. The app remains inside this root.
2. School login and direct HTTP collection create semester/course folders automatically. In the home grid, folders show the semester and course/section rather than internal course identifiers.
3. Open a PDF, write with Pencil and move with fingers. A single microphone button starts/stops recording, and the adjacent recording list plays the selected saved recording with seek/speed controls.
4. Native PKDrawing is preserved alongside vector PDF appearance and common JSON. A local recovery journal precedes coordinated PDF/commit publication. Windows reads the PDF background and common vector ink; simultaneous or incomplete commits are not silently adopted.
5. PowerPoint originals are kept; Windows PowerPoint generates versioned PDF previews. iPad can write on the separate notebook preview using original slide EMU/page identities. HTML opens in a separate script-disabled browser and can create a fixed PDF snapshot.
6. The Windows app directly checks school materials every 30 minutes while open and exposes 지금 확인. School collection does not invoke GPT. Active iPad checks every 30 minutes or 60 minutes in low-power mode; a terminated iPad does not run exact-time checks.
7. Windows 수업 정리 opens the local processor. While the app is open it starts the existing local Whisper + authenticated ChatGPT CLI pipeline at 22:00 Seoul time. The laptop must be awake. Manual runs scan the recent seven days for unprocessed lessons. ChatGPT/API limits and runtime failures remain visible; no paid AI API was added.

## Verified results

- Local JavaScript suite: 43 passed, no failures/skips.
- Final macOS CI: 25 core/integration + 12 editor/recording = 37 Swift tests, and one full app UI scenario, all passed.
- UI scenario: home, editor, recording list, page navigator, document tabs, school controls, HTML material and fixed snapshot editor.
- Native-export comparison: a synthetic stroke generated with the real PKDrawing API was exported by Swift. Source SHA and identity were validated. At 100/200/400%, Windows DOM endpoint error was 0px; blue-ink bounds differed from native PDF by 1px at each zoom. This is not a hardware handwriting or pencil-texture equivalence claim.
- Real Windows school profile: seven current-semester courses, final 92 class files / 414,995,307 bytes, all 92 SHA256 values verified. Decorative site/profile icons and confirmed duplicate imports are preserved in hidden recovery storage rather than deleted. Unmodified original class files remain intact.
- App restart retained PLATO login through a user-scoped DPAPI-protected session file. Server-expired sessions still require login.
- Actual PPTX previews: 101 and 83 slides; the 101-slide material opened at page 100 and 400% in Windows. Synthetic 4:3, 16:9 and portrait PowerPoint previews preserved original hashes and aspect ratios.
- The iOS18.5 simulator startup issue was traced to WebKit bug 293831. Only simulator app build invocations use minimum18.4 as the documented workaround. The device IPA remains minimum17.0.

## Remaining acceptance checks

- PLATO live collection is verified. A single integrated SSO login producing both PLATO and student-portal sessions is not yet verified; identical student IDs do not make the service cookies interchangeable. Fresh timetable request generation still needs the separate integrated school session. The implementation and official envelope tests exist; do not describe the live timetable API as finished.
- Assignment detail/attachments are collected. A normalized combined deadline calendar is not complete.
- Real Apple Pencil pressure/eraser/finger movement, microphone permissions/background audio, physical iCloud two-device/offline/conflict recovery, full real-lecture AI processing and next-semester server behavior need installation/device checks. Phase8 is not complete from simulator tests alone.
- Cross-platform pencil texture and variable-opacity compositing are approximations; native archives are retained. HWP/HWPX/ZIP collection is distinct from platform preview support. Long HTML over 18000px is rejected rather than silently truncated. Changed source material revisions do not automatically migrate older ink.

See [implementation details](INKDRIVE-2-IMPLEMENTATION.md) and [school synchronization](CAMPUS-SYNC.md). Older Expo instructions are historical and do not apply to this IPA.