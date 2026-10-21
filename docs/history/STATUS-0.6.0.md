# InkDrive 0.6.0 (6) — video reference development build

Verified 2026-10-22 (Asia/Seoul). Native Swift iPad app; no Expo/Metro development server required.

## Delivered IPA

- Successful complete build: https://github.com/a44383238-lab/inkdrive-ipad/actions/runs/39626293547
- App source: `09737ce7ba52e8868a5a0e68bd2c7f1b87898a47`; subsequent documentation changes do not change the IPA.
- Version 0.6.0 (6), `app.inkdrive.notes`, arm64, minimum iOS17, unsigned for Sideloadly.
- 1,470,426 bytes; SHA-256 `30b9974ff3b6bb495bc1aeaf33abfbbc960c9185ec904de64134a838134ad30a`.
- Verified matching copies on Desktop and in outputs as `InkDrive 개발용.ipa`. Previous 0.5.0 IPA and report preserved in outputs. Update the existing app; deleting the app is not required.

## Rebuilt from the video

Charcoal library/sidebar; persistent colored folders; real PDF thumbnails; recent/favorites; selection and folder destination picker; bottom-right creation menu. Compact editor header/tabs, movable and rotatable black toolbar, original colored pen nib artwork, width values and fine 0.1px controls, anchored tool-family/color/opacity panels, presets and tool removal. Recording popover plus playback dock, ±10 seconds and speed controls. Whole-page initial fit, preserved manual zoom, finger pan/pinch without inertial drift, page scrubber with live ink previews, page overview with document sidebar, paper insertion/reorder/delete and outline/bookmark/search.

See [observed flow mapping](../VIDEO-REFERENCE.md). Private recording/frames remain outside Git; CI screenshots use synthetic documents.

## Final verification

- 30 core/integration + 17 editor/recording = **47 Swift tests**, all passed.
- Complete native application scenario passed, including toolbar orientation and family switching, recording list, page overview, inserting/opening yellow paper, document tabs, school controls, HTML material and fixed snapshot.
- New paper regression was observed failing before the fix: copied inserted pages lost their PDF backing and saved white backgrounds. Retaining vector template documents and inserting backed pages fixed direct/inserted/reopened/preview color checks. Final UI screenshots confirm yellow paper in both the overview and editor.
- Move regressions cover lesson references, destination collisions, descendant rejection, hidden preview adapters, unreadable catalogs and individually moved source/notebook sidecars. Partial rollback preserves local recovery details.
- IPA ZIP CRC/receipt, native arm64 executable, bundle/version/platform and minimum OS verified. Final source symbols and absence of a JavaScript development bundle checked.
- The optional earlier macOS26 run timed out during cold simulator startup; authoritative final validation above passed on macOS15. No failing test was skipped to publish this artifact.

## Preserved features and limits

Native PencilKit drawing, PDF/iCloud commits, recovery journals, page/document identity and school synchronization remain. Windows helper and AI runtime were not changed by this UI rebuild; unrelated ASR edits in the shared checkout were not included.

The recording has no actual handwriting strokes. Physical Pencil pressure, latency, palm rejection and microphone quality require iPad confirmation. Simulator verification does not establish exact physical equivalence to the reference app. Undisclosed store/account internals are not inferred from the video.

Previous integrated backend verification is preserved in [0.5.0 history](STATUS-0.5.0.md), dated separately; it is not a new school-data refresh.
