# Video reference rebuild

Goal: rebuild the iPad library and editor around the supplied 155-second recording, retaining safe PDF/iCloud commits and school synchronization.
Architecture: SwiftUI library, UIKit/PDFKit/PencilKit editor. Execute inline. Private video and frames stay outside Git.

## Observed specification
- 00:02–00:29 / 02:26–02:34: charcoal sidebar (~18% width), document/recent/favorite navigation, colored flat folders, actual page thumbnails, compact filenames, gold selection, floating bottom-right add menu. Selection has per-item circles and bulk actions; folder navigation retains sidebar.
- 00:34–01:20: thin dark header and document tabs; black movable toolbar with colored pen nibs and small width values. Repeated tool tap opens an anchored dark panel: width in px, opacity, palette, tool removal. Toolbar can rotate vertically.
- 01:21–01:34: paper zoom/pan; compact recording/playback strip at upper right; anchored recording list and playback rates.
- 01:35–01:46: display settings and toolbar customization popovers; avoid large modal sheets for everyday controls.
- 01:50–02:12: page movement, bottom scrubber with page preview, zoom stays under user control.
- 02:13–02:25: thumbnail page browser and page insertion with paper templates; return to the document and switch tabs.
- No actual handwriting strokes are demonstrated in this clip. Pressure/latency/texture equivalence cannot be measured from it. Preserve native PencilKit, Pencil-only ink, direct-touch pan and stationary release.

## Tasks
- [x] Review every second using timestamped contact sheets; inspect key states at larger resolution.
- [x] Replace library layout, thumbnails, color folders, recent/favorites and creation access.
- [x] Rebuild compact editor chrome, pen nibs, movable/rotatable toolbar and anchored tool panels.
- [x] Integrate recording popover, page scrubber/preview, display controls and page browser.
- [x] Update meaningful UI scenarios, run device build + simulator checks, inspect screenshots against reference, deliver IPA.

## Decisions
- User's video takes precedence over generic design recommendations. UI skill search returned a marketing layout; discard it as unsuitable.
- Existing handwriting document model, journals and iCloud source originals remain intact. Do not replace persistence with screenshot-based rendering.
- Keep InkDrive identity and original icon drawings; reproduce visible arrangement and interactions rather than importing another app's binary assets.
- Preserve unrelated ASR edits already present in the shared checkout.


## Verification ledger
- Original integrated source (7fefef6): device compile, 39 Swift checks and complete app scenario passed (39580774422).
- Move/adapter/preview hardening (bbbe788): device compile, 43 Swift checks and complete app scenario passed (39582210084).
- Review: one read-only whole-change review found rollback, catalog error handling, adapter remap and delayed playback defects; all four addressed before final validation.
- Screenshot correction: application-only rotated snapshots clipped the view. Final UI capture waits for landscape after launch and captures the entire display.
- Final source adds whole-page initial fit with preserved manual zoom, tool-family controls, fine width steps and non-overlapping palette targets. Validation pending; do not label the final IPA verified until this run completes.

- 2026-10-22: a new color-content regression failed on 0d7cb87: template direct rendering was yellow, but inserted page pageRef was nil and saved/preview background was white. Retain the template PDFDocument and insert its backed page rather than a copy out of a temporary source. Preserve vector paper and test direct/inserted/reopened/preview colors. UI scenario now also opens the inserted yellow page.
- Cold simulator/UI startup exceeded the optional macOS26 job's 12-minute UI-step limit once; increase the UI step allowance to 18 minutes without skipping checks. Standard macOS15 integrated validation on 24aeaa1 passed.

- Final completion: 39626293547, source 09737ce7ba52e8868a5a0e68bd2c7f1b87898a47, 47 Swift tests and full app scenario passed. Yellow paper confirmed in actual screenshots. IPA CRC/native/version/hash validated; Desktop and output copies match 30b9974ff3b6bb495bc1aeaf33abfbbc960c9185ec904de64134a838134ad30a. Comparison report created.
