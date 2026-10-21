# InkDrive 0.7 — ink and interaction revision

## Intended behavior

- The ordinary pen uses a pure black default, full opacity, and PencilKit monoline ink. The old opaque black 0.5-point preset migrates once to at least 1.5px, avoiding a subpixel default at page fit; thinner widths remain selectable. Pencil remains a separate textured tool. Paper canvases always use light appearance regardless of the dark application chrome.
- Toolbar entries have independent UUIDs and independent settings. Adding a pen never toggles off another pen. The same tool/color/width can appear more than once. A selected entry opens its own settings on a second tap. Duplicate and remove apply to that entry, not the whole tool category.
- Hold a toolbar item for 0.35 seconds and drag over another slot to reorder it. Preserve identity, selection and order in `inkdrive.toolbar.v3`. The handle still moves the entire toolbar. The legacy preset/configuration keys remain available for migration.
- Single-page mode uses horizontal direction. Finger swipe left goes forward and right goes back at page fit. While zoomed in, finger movement pans the paper. Fit is the minimum zoom; pinch-to-zoom in remains available. Page changes and viewport changes refit the page.
- All eraser input goes through the app-owned interaction layer. A translucent circular footprint tracks the Pencil during contact; no native cross cursor is used. Whole-stroke and partial erasing respect the selected target. Partial erasing subtracts the swept brush from an existing stroke mask, preserving transforms and native archive editing.
- App-owned errors, confirmations, paper menus, view settings and text forms use `InkPanelController`. Recording, document and page lists share opaque charcoal navigation. Creation and destination screens use app-owned rows. The selection palette uses the same dark surface. File/share/permission UI remains system provided.
- Short press feedback and reorder/page transitions respect Reduce Motion. Live pen strokes are never animated with delayed easing.

## Work removed from the live pen path

`canvasViewDrawingDidChange` does not encode drawings or update the document while a tool is active. A completed stroke commits once; late estimated input callbacks are still accepted. Input pauses scheduled autosaving. Drawing changes refresh their own overlay rather than invalidating the PDF view and every overlay. Autosave waits for an idle interval.

PDF saving captures immutable base bytes, identities and PKDrawing values, then creates and renders a separate PDFDocument on a utility task. Live PDFKit objects never cross queues. Main-actor PDF metadata capture and the existing commit/recovery publication still exist; this is not a claim that all storage work runs off the main actor.

Idle recording polls no longer republish unchanged values and invalidate the library twice a second; the visible recording clock updates by whole seconds. Library thumbnail generation also uses independent PDFDocuments on utility tasks and keeps its bounded cache. Device IPA builds now use Release optimization. Simulator UI tests remain Debug so their synthetic fixture is excluded from the installed Release product.

## Verification scope

Regression coverage includes solid pen configuration, light paper appearance, commits after Pencil lift, undo, autosave deferral, immutable background snapshots, eraser hit testing between samples, clipping/serialization, transformed ink, portable ink export, duplicate toolbar entries, reorder/selection identity, page bounds and the minimum zoom.

The full application scenario checks actual left/right page gestures, another colored pen added through the menu, a long-press reorder, and persisted order after process restart, in addition to existing document/recording/page/school/HTML flows. Build receipt and verified counts are recorded in STATUS.md only after the complete pipeline succeeds.

Simulator tests do not measure physical Pencil latency, pressure, palm rejection or microphone quality. Those remain device checks. The school/Windows/AI pipeline is preserved; unrelated local ASR edits are excluded from this revision.
