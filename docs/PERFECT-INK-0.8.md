# InkDrive 0.8 — pressure-sensitive solid ink

## Engine and compatibility

The ordinary pen is a native Swift adaptation of Perfect Freehand 1.2.3 (MIT; attribution in `ThirdParty/perfect-freehand-LICENSE.txt`, also included in the device app). No JavaScript runtime is used. Six generated golden fixtures compare the Swift outline vertices with upstream 1.2.3: variable pressure, corners, dot, circle, reversal and crossing.

The chosen profile uses real Pencil pressure, thinning 0.6, outline smoothing 0.35, streamline 0, round caps and no artificial taper. The two-input-point case interpolates actual endpoint pressure rather than replacing it with simulated/default pressure. New pen strokes always fill at full opacity; pressure only changes geometry. Legacy pencil and marker tools retain their native canvas. Existing documents remain readable.

Confirmed/coalesced Pencil samples are timestamp ordered and checked for nonfinite values and impossible isolated jumps. Predicted/late estimated locations are not committed. Screen updates run at display cadence up to the device maximum of 120Hz; full-document serialization, saving and undo publication do not run in the moving pen callback. Finger scroll/pinch is disabled during Pencil contact and restored on lift/cancel. The page scroll views have directional locking disabled and release velocity removed.

## One visible shape across screen and PDF

Editable PKStroke carriers use fountain-pen ink plus an outline mask. They are filtered out of the legacy PKCanvasView. App-owned vector layers fill those outlines directly, including their fill rule and transform; PDF appearance and portable SVG use the same visible mask. Carrier opacity is PencilKit shader metadata and is intentionally ignored by this renderer. Actual pixel tests verify opaque black output and a hollow circle.

Native serialization can also canonicalize a constant-pressure carrier's ink type. Explicit owned-stroke indices are recorded before encoding: PDF annotations retain the original drawing key plus `InkDrivePerfectInkV1`; clipboard and commit archives use the versioned `NativeInkArchive` wrapper. Commit descriptors declare `nativeEncoding: inkdrive.archive.v1`. Decoding validates these indices and restores owned carriers without converting legacy ink. Vector layers use real stroke bounds and transformed origins, and live preview layers use the page bounds, so snapshots and clipping preserve their appearance.

PKDrawing serialization canonicalizes path winding/start points and quantizes mask coordinates. Archive tests verify pressure retention, bounding error within 0.15pt and less than 2% integrated alpha-coverage difference at 4x, rather than assuming identical path command arrays. The upstream algorithm fixtures are compared before this native archive canonicalization. Portable output includes an authoritative optional `outline` and its fill rule (`maskEvenOdd`); samples retain pressure and actual nib dimensions. Old unmasked strokes keep their existing rendering.

Whole/partial erasing, clipping under transforms, recoloring, width changes, copy/paste, undo/redo and PDF reopening retain the editable carrier. Width changes preserve the already erased area. Lasso resizing/moving previews app-owned ink while dragging, then commits its transform on release. The hybrid legacy/native display keeps new solid pen ink above legacy pencil/highlighter drawing; the stored stroke sequence is preserved for document export.

## Hold to shape

Keep the Pencil in contact after drawing. A 1.5-second hold, with 3 screen points of jitter tolerance, attempts a straight line, circle or rotated rectangle. It does not snap merely because time passed after lifting the Pencil. Fit checks reject incomplete loops and scribbles. After snapping, lifting commits a uniform-width geometric outline and enters lasso selection. Corner dragging resizes; the selection palette changes color and width. Holding a straight stroke preserves its endpoints. The first engine migration selects the existing black pen at at least 1.5px once; independent tool identities/order are preserved.

## Saving and verification boundary

The new pen tracks drawing changes without serializing the entire page after each lift. Legacy callbacks compare their native subset only. Background PDF jobs use immutable snapshots and independent PDFDocuments. Recovery writes, content hashing, independent commit publication and portable export run on a utility executor; commit head state is protected by a lock. Initial/structural PDF metadata capture still happens on the owning actor.

The automated scenario uses synthetic documents and strokes, excluded from Release. Simulator results do not measure physical Pencil latency, pressure calibration, ProMotion behavior or palm rejection on the user's iPad. Final successful run, artifact checksum and delivered copies are recorded in STATUS only after verification.
