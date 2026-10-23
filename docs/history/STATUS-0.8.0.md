# InkDrive 0.8.0 (8) — pressure-sensitive solid ink

Verified and delivered 2026-10-23 (Asia/Seoul). Native Swift Release application; no development server.

## Delivered IPA

- Successful complete pipeline: https://github.com/a44383238-lab/inkdrive-ipad/actions/runs/39712840240
- App source: `491b231501b29ee1db39eb5ecc112a4486acfeb0`. Later documentation-only commits do not change the binary.
- `app.inkdrive.notes`, arm64, iOS 17 minimum, unsigned for signing/installing with Sideloadly.
- 1,040,888 bytes; SHA-256 `049ca1eafb34d4c896b62b28af979c718847d70b26b168f996446be8968baff5`.
- Matching Desktop/output copies named `InkDrive 개발용.ipa`; previous 0.7.0 IPA and reports backed up. Install over the existing app using its existing signing identity to retain app data.

## Changes

- The ordinary pen now uses a native Swift adaptation of Perfect Freehand 1.2.3. Actual pressure changes width; the visible outline fills in opaque solid color. Black is pure black. Pencil and marker retain their existing tools.
- Holding the Pencil on the screen for 1.5 seconds after drawing recognizes a line, circle or rotated rectangle. Lifting selects the shape with the lasso. Corner resizing and movement preview the actual ink; the selection menu changes color and width.
- Confirmed/coalesced input is timestamp ordered; stale, nonfinite and impossible isolated jumps are rejected. Display updates follow device cadence up to 120Hz. Finger pan/pinch pauses during Pencil contact.
- Paper panning has no initial-axis directional lock; release velocity is removed. Existing horizontal single-page swipes and zoom-in behavior remain.
- Native archive ownership metadata preserves custom ink across PDF reopening, clipboard and commit publication. Whole/partial erasing, masks, transforms, width changes and undo retain editable ink.
- The live pen path does not serialize the page. Recovery and commit publication use a background utility executor with independent PDF snapshots. Existing independent toolbar entries and long-press order are preserved.

Implementation, rendering boundaries and compatibility: [engine notes](PERFECT-INK-0.8.md).

## Verification

- **77 native Swift tests, zero failures.** Includes six upstream geometry fixtures, actual opaque-black pixels, archive/PDF reopening, pressure retention, partial erase and width changes, 1.5-second timer, shape selection/editing, jump rejection, palm input lock, free-axis panning and background publication.
- Actual layer rasterization verified an opaque hollow ring and moved ink during selection preview. The raw Quartz bitmap reverses the vertical row order; the test checks visible coverage, horizontal bounds, hollow center and translation rather than a mistaken row index. No visible-ink assertion was skipped.
- Full standalone app interaction scenario passed, including page swipes, independent colored-tool addition, long-press reorder and relaunch persistence, recording/page/school/HTML navigation.
- 11 shared-format/commit/vector tests passed locally. Final library/editor/tool-settings/reordered-toolbar screenshots inspected; the synthetic black/blue/red pressure waves and hollow circle render clearly.
- ZIP CRC, artifact and local SHA-256, bundle/version, arm64 device platform, minimum OS, license attribution and exclusion of JavaScript/development runtime and Release test seeds verified.

## Limits

The simulator does not measure physical Pencil latency, pressure calibration, ProMotion or palm rejection on the user's iPad. The screenshots contain synthetic strokes. Main-actor PDF metadata capture remains for initial/structural snapshots. The hybrid display puts new solid pen ink above legacy pencil/highlighter layers; stored stroke order is retained for export.

School/Windows/AI work is preserved, not newly live-verified by this change. Unrelated local ASR edits were excluded. Previous delivery evidence: [0.7.0 history](history/STATUS-0.7.0.md).
