# InkDrive 0.8.1 — recent previews, contact endings and folder transitions

## Evidence and changes

The supplied library screenshot showed a fallback document preview extending outside a recent-file row and covering neighboring labels. The same `DocumentThumbnail` had an 80×112pt placeholder inside a parent proposing 23×30pt. A fixed child frame can exceed the parent's proposal. The preview now owns its target dimensions, constrains both loaded PDF images and fallback artwork to those bounds, and clips overflow. The sidebar requests 23×30pt; document tiles request 104×148pt. Reused preview state resets when the entry/revision changes.

The supplied recording showed irregular small writing and narrow tails at stroke endings. Code inspection found that the same append loop accepted coalesced contact samples and the final ended callback, including zero-force lift locations. The existing impossible-jump threshold intentionally tolerated short movement and therefore did not reject these short tails. The contact path now rejects ended/cancelled and zero-pressure samples before appending. While a precise location still expects estimation updates, the regular touch location is used. Coalesced contact samples and actual pressure remain; predicted samples are not committed.

Visible outlines previously connected every Perfect Freehand boundary vertex with a straight segment. The new path uses quadratic segments between adjacent midpoints, with each boundary vertex as its control point. This makes the outline tangent-continuous without adding a centerline filtering delay or reducing opacity. Upstream boundary-vertex golden fixtures remain unchanged. The authoritative curve path is shared by live preview, committed layers, PDF appearance and portable export. Existing stored masks are not regenerated on open.

The document grid uses folder-path identity and a directional 0.16-second ease-out transition: 18pt insertion, 10pt removal and opacity. Returning to a parent reverses direction. The Reduce Motion setting uses opacity only for 0.1 seconds. There is no timer, interaction lock or navigation delay; the transition applies to the document area while the sidebar remains stable.

## Checks

New native regressions exercise an ordinary short ending that would pass the older teleport filter, a zero-force callback, and an actual overlay commit. They verify that no tail reaches the archive and that the last contact position/pressure remain. Another check verifies a closed quadratic outline, a rounded corner, a filled interior and bounded geometry. Existing opacity, circle rasterization, pressure, PDF reopening, erasing, hold recognition, selection editing, undo, portable output and free-axis panning checks remain enabled.

The standalone UI fixture includes recent PDF, text and HTML documents. Its scenario checks the recent text row dimensions and captures the recent previews after folder entry/return. Final screenshots must be inspected before delivery. These are simulator checks and synthetic traces, not a measured replay of the user's physical Pencil input. Input improvement on the actual iPad remains a device check. Delivery run and checksum are recorded in STATUS after successful verification.
