# InkDrive 0.7.0 (7) — solid ink and interaction revision

Verified 2026-10-22 (Asia/Seoul). Native Swift iPad app, optimized Release device build; no development server.

## Delivered IPA

- Complete successful pipeline: https://github.com/a44383238-lab/inkdrive-ipad/actions/runs/39641837661
- App source: `47ef037cbf5046531bbfcd47e923e64975e4db96`. Subsequent documentation-only commits do not change the delivered binary.
- `app.inkdrive.notes`, arm64, minimum iOS17, unsigned for signing/installing with Sideloadly.
- 979,399 bytes; SHA-256 `005b846a64d3448120a0abfea9c46f203813a5bd404596b2454479f1c7dfc201`.
- Matching Desktop/output copies named `InkDrive 개발용.ipa`; previous 0.6.0 IPA/report backed up. Update the existing app to preserve its data; deleting the app is not required.

## Changes

- Pure black monoline pen, light paper canvas, full-opacity default. Old opaque black subpixel preset migrates once to at least 1.5px; finer widths remain selectable.
- Independent toolbar entries for any number of same-kind pens and colors/widths. Add always adds; repeated tap edits that entry; duplicate/remove act on that entry.
- Long-press reorder uses a stable parent gesture, a moving preview, shared visual/accessibility order and an unthrottled final drop. Entry identity and selected pen survive reordering and process restart.
- Single-page mode swipes left/right; zooming in pans the paper. Fit is the minimum scale, with refit on page/viewport change and manual zoom-in retained during ordinary layout.
- App-owned circular eraser footprint replaces the native cross cursor. Whole-stroke/partial erasing, target filtering, transform-aware clipping and archive preservation are covered.
- Shared charcoal menus, confirmations, settings and navigation, custom creation/destination screens and color entry. Short press/reorder/page feedback respects Reduce Motion. Empty playback docks stay hidden.
- Drawing callbacks do not encode/commit during active input. Completed drawing refreshes only its own overlay. Scheduled autosave pauses while input is active. PDF render jobs and library thumbnails use independent background PDFDocuments. Idle recording polling no longer republishes unchanged state twice per second.

Implementation and precise boundaries: [ink and interaction notes](INK-INTERACTION-0.7.md). Original reference mapping: [video observations](VIDEO-REFERENCE.md).

## Verification

- **59 native Swift tests, zero failures.** Includes existing PDF/storage/campus behavior plus solid ink, input deferral, frozen background saves, clipped erasing and independent toolbar identities/order.
- Full app UI scenario passed: actual left/right swipes, another colored pen added, long-press relocation to the first slot, matching visual order and restored identity after app relaunch, alongside document/recording/page/school/HTML flows.
- Tests first reproduced the old pen/color/live-commit behavior. The UI test caught an incomplete drag drop; final-drop resolution now bypasses animation throttling. No failing assertion was skipped for delivery.
- IPA ZIP CRC, checksum receipt, bundle/version, native arm64/platform/minimum OS, no JavaScript runtime and matching local copies verified. Actual final screenshots inspected.

## Limits and preserved work

Physical Pencil latency, pressure, palm rejection and microphone quality still require the iPad. Simulator results do not establish a measured physical latency or perfect equivalence to the reference app. Main-actor PDF metadata capture and existing commit/recovery publication remain; not all storage work is off the UI actor.

School/Windows/AI behavior is preserved and is not a new live school-sync verification. Unrelated local ASR edits were excluded. Earlier delivery evidence is retained in [0.6.0 history](history/STATUS-0.6.0.md) and [0.5.0 backend history](history/STATUS-0.5.0.md).
