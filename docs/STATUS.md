# InkDrive 0.8.1 (9) — recent previews, pen endings and folder transitions

Verified and delivered 2026-10-23 (Asia/Seoul). Optimized native Swift Release application; no development server.

## Delivered IPA

- Successful IPA recovery build: https://github.com/a44383238-lab/inkdrive-ipad/actions/runs/39900376712
- Exact-source device compile, native tests and full UI tests passed in https://github.com/a44383238-lab/inkdrive-ipad/actions/runs/39898880397. That run failed only when finalizing its artifact upload (`ECONNRESET`). Recovery verified those passed stages and the exact commit, then rebuilt that source and delivered the IPA. The original test logs and screenshots are retained as verification evidence.
- Application source: `fba1e2e0d5712c6abe4a8cfcc8ca0206014fc74a`. Documentation-only commits after this source do not change the binary.
- `app.inkdrive.notes`, arm64 device build, iOS 17 minimum, unsigned for signing/installing with Sideloadly.
- 1,049,279 bytes; SHA-256 `cc18f8eedb64ed0d9811b4f2abb0aef27473bbbb44932500390eb78e44154939`.
- Matching Desktop/output copies named `InkDrive 개발용.ipa`. The previous 0.8.0 IPA and reports are backed up. Install over the existing app using the same signing identity to preserve app data.

## Changes

- Recent-file previews have an explicit 23×30pt target and clipping for both loaded PDFs and fallback artwork. Small non-PDF previews no longer exceed their row and cover filenames. Document tiles have their own 104×148pt target.
- The pen contact path excludes ended/cancelled and zero-pressure callbacks. Still-estimated precise positions use the regular touch location. This addresses short lift tails that fit under the existing impossible-jump threshold.
- Visible pressure outlines use tangent-continuous quadratic segments instead of straight polygon edges. Actual pressure still controls width; ink remains opaque solid color. Existing stored masks are not redrawn on open.
- Folder entry/return uses a directional 0.16-second ease-out slide and fade in the document area. Reduce Motion uses a short opacity transition. No navigation timer or interaction lock was added.

Detailed evidence and scope: [0.8.1 notes](UI-PEN-0.8.1.md). Previous engine architecture: [0.8 engine notes](PERFECT-INK-0.8.md).

## Verification

- **79 native Swift tests, zero failures.** New tests exercise short lift tails and zero-pressure input through the actual overlay commit and verify smooth, closed and bounded outline geometry. Existing pressure, opaque pixels, hollow-circle rendering and selection preview, archive/PDF reopening, erasing, hold recognition, undo, portable export and paper navigation checks remain enabled.
- The complete app UI scenario passed, including compact recent text previews, folder entry/return, independent colored pens, long-press reorder and relaunch persistence, page/recording/school/HTML flows.
- 11 shared-format/commit/vector tests passed locally.
- Final recent-file, editor and pen-settings screenshots inspected before replacing the IPA. They contain synthetic fixture strokes and recent PDF/text/HTML documents.
- ZIP CRC, remote artifact/local SHA-256, version/build, arm64 device platform, minimum OS, and exclusion of JavaScript/development runtime and Release test fixtures verified.

## Boundaries

The simulator does not measure physical Pencil latency or prove that the user's exact handwriting is reproduced. Actual iPad pressure feel and ending behavior remain a device check. Existing documents, ink masks, recording/campus/Windows/AI work and independent toolbar identities/order are preserved; those services were not newly live-verified. Unrelated local ASR edits were excluded.

Previous complete delivery evidence: [0.8.0 history](history/STATUS-0.8.0.md).
