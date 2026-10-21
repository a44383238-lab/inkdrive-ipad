# iPad video reference, 2026-10-21

The private source is a 155-second, 2388×1668 screen recording. It was inspected at one-second intervals across the whole clip, with larger keyframes for the library, tool panels, recording controls, settings and page overview. The recording and extracted frames are not included in this public repository.

## Rebuilt surfaces

| Reference | InkDrive implementation |
| --- | --- |
| 00:02–00:29, 02:26–02:34 | Charcoal document library, persistent sidebar, colorful folders, actual PDF thumbnails, compact filenames, gold selection circles, recent documents, favorites, bottom-right creation menu and destination browser |
| 00:34–01:20 | Compact header and document tabs, movable black toolbar, original colored nib drawings with width values, horizontal/vertical toolbar orientation, anchored tool settings, color palette and recent colors, opacity/width sliders, tool-family selection, presets and tool removal |
| 01:21–01:34 | One-tap recording, anchored recording catalog, playback controls, ±10 seconds, playback rates, persistent small playback strip while writing |
| 01:35–01:46 | Display controls and toolbar customization accessible from compact popovers |
| 01:50–02:12 | Finger pan/pinch, stationary release without inertial drift, page scrubber with ink-aware preview and page count |
| 02:13–02:25 | Page thumbnail grid, document sidebar, page insertion after current page, white/ruled/grid/yellow ruled paper, page reorder/delete menu, search/outline/bookmarks navigator |

## Data and behavior contracts

- PencilKit remains the actual drawing engine. Pencil input draws; direct finger input pans/zooms. No screenshot or web-canvas replacement.
- Native drawings, source documents, document/page identities, lossless ink, autosave journals and iCloud commit checks remain intact.
- Page thumbnails include current unsaved drawing without adding annotations to the live PDF model.
- Moving library items updates lesson PDF/material/audio references and affected adapter paths. Destinations and manifests are checked before mutation; failures attempt every rollback step, with local recovery records for incomplete rollback.
- Dismissing the recording popover leaves playback available in the document. Closing or switching documents cancels pending audio loads and stops playback. Recording capture has its independent lifecycle.
- Existing school synchronization remains accessible through the sidebar.

## Verification limits

The clip contains tool configuration and paper navigation, but no actual handwriting strokes. Physical Pencil latency, pressure response, texture, palm rejection and microphone quality cannot be measured from it or from the Windows host. Simulator tests cover native routing, persistence and interaction; they do not establish physical equivalence to the reference app.

The source shows additional menus without exercising every option. InkDrive reproduces the observed working flows and retains its own name/assets. Store/account pages and undisclosed proprietary internals are not reconstructed from guesswork.
