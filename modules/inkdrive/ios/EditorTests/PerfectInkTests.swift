import XCTest
import UIKit
import PencilKit
import PDFKit
@testable import InkDriveCore

@MainActor final class PerfectInkTests: XCTestCase {
    private func line() -> [InkSample] {
        (0...40).map { InkSample(point: CGPoint(x: 20 + $0 * 3, y: 60), pressure: 0.05 + CGFloat($0) / 45, time: Double($0) / 120) }
    }
    private func editor() throws -> EditorViewController {
        let model = try PDFModel(data: PDFModel.blank(template: .plain))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let editor = EditorViewController(session: EditorSession(model: model, store: CoordinatedStore(url: url), digest: "test"))
        editor.loadViewIfNeeded(); editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768); editor.view.layoutIfNeeded()
        return editor
    }
    private func pixels(_ stroke: PKStroke, scale: Int = 1) throws -> [UInt8] {
        let width = 160 * scale, height = 120 * scale
        var pixels = [UInt8](repeating: 0,count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: CGFloat(scale),y: CGFloat(scale))
            VectorInkPainter.draw(PKDrawing(strokes: [stroke]),in: context)
        }
        return pixels
    }
    func testSwiftOutlineMatchesUpstream123ReferencePolygons() throws {
        struct Fixture: Decodable { let name: String; let input: [[Double]]; let expected: [[Double]] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "perfect-freehand", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            let samples = fixture.input.enumerated().map { i, p in InkSample(point: CGPoint(x: p[0], y: p[1]), pressure: p[2], time: Double(i) / 120) }
            let actual = PerfectFreehand.outline(samples, size: 3)
            XCTAssertEqual(actual.count, fixture.expected.count, fixture.name)
            guard actual.count == fixture.expected.count else { continue }
            for (point, expected) in zip(actual, fixture.expected) {
                XCTAssertEqual(point.x, expected[0], accuracy: 0.000001, fixture.name)
                XCTAssertEqual(point.y, expected[1], accuracy: 0.000001, fixture.name)
            }
        }
    }
    func testPressureChangesWidthButNeverChangesInkOpacity() throws {
        let stroke = try XCTUnwrap(PerfectInk.make(line(), width: 4, color: UIColor.black.withAlphaComponent(0.2)))
        XCTAssertTrue(PerfectInk.owns(stroke)); XCTAssertEqual(stroke.ink.color.cgColor.alpha, 1)
        // PencilKit normalizes a fountain-pen carrier's internal opacity. The owned renderer
        // deliberately ignores that shader metadata and fills the visible outline at full alpha.
        let rendered = try pixels(stroke), center = (60 * 160 + 128) * 4
        XCTAssertEqual(Array(rendered[center..<center+4]),[0,0,0,255])
        XCTAssertGreaterThan(PerfectFreehand.radius(size: 4, pressure: 0.9), PerfectFreehand.radius(size: 4, pressure: 0.1) * 2)
        let path = PerfectInk.outline(stroke)
        XCTAssertTrue(path.contains(CGPoint(x: 128, y: 62)))
        XCTAssertFalse(path.contains(CGPoint(x: 35, y: 62)))
    }
    func testNativeArchiveAndPDFPreserveVisibleOutlineAndPressure() throws {
        let stroke = try XCTUnwrap(PerfectInk.make(line(), width: 4, color: .black))
        let drawing = PKDrawing(strokes: [stroke]), restored = try NativeInkArchive(drawing).decode()
        let reopenedStroke = try XCTUnwrap(restored.strokes.first)
        XCTAssertTrue(PerfectInk.owns(reopenedStroke), "Archive carrier must remain identifiable after reopening")
        // PKDrawing canonicalizes mask winding/start points and quantizes coordinates on archive.
        // Check the visible coverage at 4x and bounded geometric error, not command ordering.
        let before = try pixels(stroke,scale: 4), after = try pixels(reopenedStroke,scale: 4)
        var coverage = 0.0, difference = 0.0
        for index in stride(from: 3,to: before.count,by: 4) {
            coverage += Double(before[index]); difference += abs(Double(before[index]) - Double(after[index]))
        }
        XCTAssertLessThan(difference / max(1,coverage),0.02)
        let a = PerfectInk.bounds(stroke), b = PerfectInk.bounds(reopenedStroke)
        XCTAssertEqual(a.minX,b.minX,accuracy: 0.15); XCTAssertEqual(a.maxY,b.maxY,accuracy: 0.15)
        XCTAssertEqual(reopenedStroke.path.first?.force ?? 0, 0.05, accuracy: 0.00001)
        let model = try PDFModel(data: PDFModel.blank(template: .plain)); model.pages[0].drawing = drawing
        let reopened = try PDFModel(data: model.snapshot())
        XCTAssertTrue(PerfectInk.owns(try XCTUnwrap(reopened.pages[0].drawing.strokes.first)))
        XCTAssertEqual(reopened.pages[0].drawing.strokes.count, 1)
    }
    func testCustomInkPartialEraseTransformAndRewidthPreserveTheErasedArea() throws {
        let stroke = try XCTUnwrap(PerfectInk.make(line(), width: 4, color: .black))
        let erased = InkEraser.erase(PKDrawing(strokes: [stroke]), from: CGPoint(x: 80, y: 60), to: CGPoint(x: 80, y: 60), width: 12, partial: true, target: "all")
        let result = try XCTUnwrap(erased.strokes.first)
        XCTAssertFalse(PerfectInk.outline(result).contains(CGPoint(x: 80, y: 60)))
        XCTAssertTrue(PerfectInk.outline(result).contains(CGPoint(x: 50, y: 60)))
        let wider = PerfectInk.rewidth(result, width: 8)
        XCTAssertFalse(PerfectInk.outline(wider).contains(CGPoint(x: 80, y: 60)))
        let moved = PKStroke(ink: result.ink, path: result.path, transform: CGAffineTransform(translationX: 0, y: 90), mask: result.mask)
        XCTAssertTrue(InkEraser.erase(PKDrawing(strokes: [moved]), from: CGPoint(x: 50, y: 150), to: CGPoint(x: 50, y: 150), width: 12, partial: false, target: "all").strokes.isEmpty)
    }
    func testPortableInkIncludesExactOutlineAndActualWidths() throws {
        let stroke = try XCTUnwrap(PerfectInk.make(line(), width: 4, color: .black)), drawing = PKDrawing(strokes: [stroke])
        let data = try PortableInkExporter.document(drawing: drawing, documentID: UUID(), pageID: UUID(), strokeIDs: [UUID()], sourceSHA256: String(repeating: "a", count: 64), crop: CGRect(x: 0,y: 0,width: 595,height: 842), rotation: 0, revision: 1, createdAt: Date(timeIntervalSince1970: 1))
        let output = try XCTUnwrap(data.pages[0].strokes.first)
        XCTAssertNotNil(output.outline); XCTAssertEqual(output.opacity, 1); XCTAssertEqual(output.tool, "pen")
        XCTAssertTrue(output.samples.allSatisfy { $0.opacity == 1 })
        XCTAssertLessThan(output.samples.first!.width, output.samples.last!.width)
        let adapter = DocumentAdapter(kind: "html-snapshot", originalPath: "test", originalSHA256: String(repeating: "a", count: 64), width: 1190, height: 1684)
        let converted = try adapter.convert(data.pages[0], index: 0)
        XCTAssertEqual(converted.strokes[0].outline?[0][1], (output.outline?[0][1] ?? 0) * 2)
    }
    func testLateOrInvalidSamplesCannotJumpAnExistingStroke() {
        var input = InkInputBuffer()
        XCTAssertTrue(input.append(InkSample(point: CGPoint(x: 20,y: 20),pressure: 0.2,time: 1)))
        XCTAssertTrue(input.append(InkSample(point: CGPoint(x: 22,y: 21),pressure: 0.7,time: 1.01)))
        XCTAssertFalse(input.append(InkSample(point: CGPoint(x: 600,y: 600),pressure: 0.7,time: 1)))
        XCTAssertFalse(input.append(InkSample(point: CGPoint(x: CGFloat.nan,y: 30),pressure: 0.7,time: 2)))
        XCTAssertEqual(input.samples.count, 2)
    }
    func testOwnedPenCommitsOnceAndUndoRestoresPreviousDrawing() throws {
        let editor = try editor(), record = editor.session.model.pages[0], overlay = PageOverlay(record: editor.session.model.pages[0], editor: editor)
        overlay.frame = CGRect(x: 0,y: 0,width: 595,height: 842); overlay.layoutIfNeeded()
        overlay.interaction.beginPen(line()[0]); line().dropFirst().forEach(overlay.interaction.appendPen)
        XCTAssertTrue(record.drawing.strokes.isEmpty, "No serialization or session edit while the pen is moving")
        overlay.interaction.finishPen(); overlay.commit()
        XCTAssertEqual(record.drawing.strokes.count, 1); XCTAssertTrue(overlay.canvas.drawing.strokes.isEmpty)
        editor.session.history.undo(); XCTAssertTrue(record.drawing.strokes.isEmpty)
    }
    func testUnexpectedTeleportIsRejectedAndDoesNotBecomeADiagonalSpike() throws {
        let editor = try editor(), overlay = PageOverlay(record: editor.session.model.pages[0], editor: editor)
        overlay.interaction.beginPen(InkSample(point: CGPoint(x: 30,y: 40), pressure: 0.5,time: 1))
        overlay.interaction.appendPen(InkSample(point: CGPoint(x: 8000,y: 8000), pressure: 0.5,time: 1.001))
        overlay.interaction.appendPen(InkSample(point: CGPoint(x: 35,y: 42), pressure: 0.5,time: 1.01))
        overlay.interaction.finishPen(); overlay.commit()
        let stroke = try XCTUnwrap(editor.session.model.pages[0].drawing.strokes.first)
        XCTAssertLessThan(PerfectInk.bounds(stroke).maxX, 100)
    }
    func testHoldGateWaitsExactlyOneAndAHalfSecondsAndIgnoresSmallJitter() {
        var gate = InkHoldGate(); XCTAssertTrue(gate.update(CGPoint(x: 10,y: 10),at: 5,scale: 2))
        XCTAssertFalse(gate.ready(at: 6.499)); XCTAssertTrue(gate.ready(at: 6.5))
        XCTAssertFalse(gate.update(CGPoint(x: 10.5,y: 10),at: 6,scale: 2))
        XCTAssertTrue(gate.update(CGPoint(x: 15,y: 10),at: 6.6,scale: 2))
        XCTAssertFalse(gate.ready(at: 7)); XCTAssertTrue(gate.ready(at: 8.1))
    }
    func testLineCircleAndRotatedRectangleRecognitionAndScribbleRejection() throws {
        XCTAssertEqual(InkShapeRecognizer.recognize(line(),scale: 1)?.kind,.line)
        let circle = (0...64).map { i in InkSample(point: CGPoint(x: 100 + 35*cos(Double(i)/64 * .pi*2), y: 100 + 35*sin(Double(i)/64 * .pi*2)),pressure: 0.5,time: Double(i)/120) }
        XCTAssertEqual(InkShapeRecognizer.recognize(circle,scale: 1)?.kind,.circle)
        let corners = [CGPoint(x: 30,y: 30),CGPoint(x: 130,y: 30),CGPoint(x: 130,y: 90),CGPoint(x: 30,y: 90)]
        var rect: [InkSample] = []
        for i in 0..<4 { for j in 0..<16 {
            let p = PerfectFreehand.rotate(PerfectFreehand.lerp(corners[i],corners[(i+1)%4],CGFloat(j)/16),around: CGPoint(x: 80,y: 60),by: .pi/6)
            rect.append(InkSample(point: p,pressure: 0.5,time: Double(rect.count)/120))
        }}
        rect.append(InkSample(point: rect[0].point,pressure: 0.5,time: 1))
        XCTAssertEqual(InkShapeRecognizer.recognize(rect,scale: 1)?.kind,.rectangle)
        XCTAssertNil(InkShapeRecognizer.recognize([InkSample(point:.zero,pressure:0.5,time:0)],scale:1))
        let scribble = (0...80).map { i in InkSample(point: CGPoint(x: i*2,y: Int(sin(Double(i)/2)*30)+60),pressure:0.5,time: Double(i)/120) }
        XCTAssertNil(InkShapeRecognizer.recognize(scribble,scale:1))
    }
    func testRecognizedShapeAutomaticallySelectsForColorWidthAndResize() throws {
        let editor = try editor(), overlay = PageOverlay(record: editor.session.model.pages[0], editor: editor)
        editor.provider.overlays[overlay.record.id] = overlay
        overlay.interaction.beginPen(line()[0]); line().dropFirst().forEach(overlay.interaction.appendPen)
        XCTAssertTrue(overlay.interaction.recognizeHeldShape()); overlay.interaction.finishPen(); overlay.commit()
        XCTAssertEqual(editor.tool, .lasso); XCTAssertEqual(overlay.interaction.selected.count, 1)
        let old = overlay.interaction.selectedBounds
        overlay.interaction.scaleSelection(1.5); overlay.interaction.recolor(.red); overlay.interaction.rewidth(5)
        let stroke = try XCTUnwrap(editor.session.model.pages[0].drawing.strokes.first)
        XCTAssertEqual(stroke.ink.color.hexString, "#FF0000"); XCTAssertEqual(stroke.path.first?.size.width, 5)
        XCTAssertGreaterThan(PerfectInk.bounds(stroke).width, old.width)
    }
    func testPalmCannotMoveViewportDuringPencilContact() {
        let view = UIScrollView(), viewport = NotebookViewport()
        viewport.setInkActive(true,in: view)
        XCTAssertFalse(view.panGestureRecognizer.isEnabled)
        viewport.setInkActive(false,in: view); XCTAssertTrue(view.panGestureRecognizer.isEnabled)
    }
    func testPaperPanningNeverLocksToTheInitialAxis() {
        let view = UIScrollView(); view.isDirectionalLockEnabled = true
        let viewport = NotebookViewport(); viewport.configure(view)
        XCTAssertFalse(view.isDirectionalLockEnabled)
        view.contentOffset = CGPoint(x: 83,y: 126)
        var target = CGPoint(x: 900,y: 900)
        StationaryScrollDelegate(original: nil).scrollViewWillEndDragging(view, withVelocity: CGPoint(x: 5,y: 8), targetContentOffset: &target)
        XCTAssertEqual(target, CGPoint(x: 83,y: 126))
    }
    func testActualHoldTimerSnapsAfterOneAndAHalfSeconds() async throws {
        let editor = try editor(), overlay = PageOverlay(record: editor.session.model.pages[0], editor: editor)
        overlay.interaction.beginPen(line()[0]); line().dropFirst().forEach(overlay.interaction.appendPen)
        try await Task.sleep(nanoseconds: 1_650_000_000)
        overlay.interaction.finishPen(); overlay.commit()
        XCTAssertEqual(editor.tool, .lasso)
        XCTAssertEqual(overlay.interaction.selected.count, 1)
    }
    func testCommitPublicationCanRunOffTheInputThreadWithoutLosingOutlines() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try PDFModel(data: PDFModel.blank(template: .plain))
        model.pages[0].drawing = PKDrawing(strokes: [try XCTUnwrap(PerfectInk.make(line(),width: 3,color: .black))])
        let bytes = try model.snapshot(), url = directory.appendingPathComponent("note.pdf")
        try bytes.write(to: url)
        let commits = try InkCommitStore(root: directory,documentID: model.documentID,documentURL: url)
        let background = try await Task.detached(priority: .utility) {
            let notMain = !Thread.isMainThread
            try commits.checkHead(); try commits.publish(PDFModel(data: bytes),fileBytes: bytes)
            return notMain
        }.value
        XCTAssertTrue(background)
        let objects = try FileManager.default.contentsOfDirectory(at: commits.root.appendingPathComponent("objects"),includingPropertiesForKeys: nil)
        let documents = objects.compactMap { file in (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(PortableInkDocument.self,from: $0) } }
        XCTAssertNotNil(documents.first?.pages.first?.strokes.first?.outline)
    }
    func testCustomSurfaceDisplaysSolidBlackAndKeepsTheMiddleOfACircleEmpty() throws {
        let editor = try editor(), record = editor.session.model.pages[0]
        let circle = (0...96).map { i in InkSample(point: CGPoint(x: 90 + 25*cos(Double(i)/96 * .pi*2), y: 90 + 25*sin(Double(i)/96 * .pi*2)),pressure: 0.5,time: Double(i)/240) }
        let stroke = try XCTUnwrap(PerfectInk.make(circle,width: 4,color: .black))
        let original = PKDrawing(strokes:[stroke])
        let raw = try PKDrawing(data:original.dataRepresentation())
        print("Constant-pressure native carrier after raw archive:",raw.strokes.first?.ink.inkType.rawValue ?? "missing")
        let encoded = try JSONEncoder().encode(NativeInkArchive(original))
        let archived = try JSONDecoder().decode(NativeInkArchive.self, from: encoded).decode()
        XCTAssertTrue(PerfectInk.owns(try XCTUnwrap(archived.strokes.first)))
        record.drawing = archived
        let reopened = try PDFModel(data: editor.session.model.snapshot())
        record.drawing = reopened.pages[0].drawing
        XCTAssertTrue(PerfectInk.owns(try XCTUnwrap(record.drawing.strokes.first)))
        let overlay = PageOverlay(record: record,editor: editor); overlay.frame = CGRect(x:0,y:0,width:160,height:160); overlay.layoutIfNeeded()
        var bytes = [UInt8](repeating:0,count:160*160*4)
        try bytes.withUnsafeMutableBytes { pixels in
            let context = try XCTUnwrap(CGContext(data:pixels.baseAddress,width:160,height:160,bitsPerComponent:8,bytesPerRow:640,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            overlay.layer.render(in:context)
        }
        let visible = (0..<160*160).filter { bytes[$0*4+3] > 240 }
        let rows = visible.map { $0 / 160 }, columns = visible.map { $0 % 160 }
        print("Solid ring raster bounds:",columns.min() ?? -1,rows.min() ?? -1,columns.max() ?? -1,rows.max() ?? -1,"pixels:",visible.count)
        // CALayer snapshots into a raw Quartz bitmap can invert the row order.
        // Derive the ring's raster row from its opaque coverage, then verify its
        // hollow center, expected horizontal geometry, and actual preview translation.
        XCTAssertGreaterThan(visible.count, 150,"The custom stroke must be visible and opaque on the actual layer")
        let centerRow = ((rows.min() ?? 90) + (rows.max() ?? 90)) / 2
        XCTAssertEqual(columns.min() ?? -1,63,accuracy: 2)
        XCTAssertEqual(columns.max() ?? -1,116,accuracy: 2)
        XCTAssertEqual(bytes[(centerRow*160+90)*4+3],0,"A circle is an outline, not a filled disk")
        XCTAssertGreaterThan(bytes[(centerRow*160+115)*4+3],240,"The visible circle edge must be opaque")
        overlay.previewSelection([0], by: CGAffineTransform(translationX: 20,y: 0))
        var moved = [UInt8](repeating: 0,count: bytes.count)
        try moved.withUnsafeMutableBytes { pixels in
            let context = try XCTUnwrap(CGContext(data:pixels.baseAddress,width:160,height:160,bitsPerComponent:8,bytesPerRow:640,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            overlay.layer.render(in:context)
        }
        XCTAssertEqual(moved[(centerRow*160+115)*4+3],0,"The actual ink must leave its previous position during selection preview")
        XCTAssertGreaterThan(moved[(centerRow*160+135)*4+3],240,"Selection preview moves the visible ink, not just the bounding box")
    }
    func testArchiveRejectsInvalidOwnershipAndPreservesLegacyInk() throws {
        let stroke = try XCTUnwrap(PerfectInk.make(line(), width: 4, color: .black))
        let drawing = PKDrawing(strokes: [stroke])
        XCTAssertThrowsError(try NativeInkArchive.restore(drawing, perfect: [1]))
        XCTAssertThrowsError(try NativeInkArchive.restore(drawing, perfect: [0,0]))
        let legacy = PKStroke(ink: PKInk(.pen,color: .blue),path: stroke.path)
        let mixed = PKDrawing(strokes: [legacy,stroke])
        let archive = try JSONDecoder().decode(NativeInkArchive.self,from: JSONEncoder().encode(NativeInkArchive(mixed)))
        let restored = try archive.decode()
        XCTAssertFalse(PerfectInk.owns(restored.strokes[0]))
        XCTAssertTrue(PerfectInk.owns(restored.strokes[1]))
    }
    func testLiftAndZeroPressureCallbacksCannotAddAShortTail() throws {
        let editor = try editor(), record = editor.session.model.pages[0]
        let overlay = PageOverlay(record: record, editor: editor)
        overlay.interaction.beginPen(InkSample(point: CGPoint(x:20,y:20),pressure:0.5,time:1))
        overlay.interaction.appendPenContact(InkSample(point: CGPoint(x:22,y:23),pressure:0.6,time:1.01),lifted:false)
        // Both are short enough to pass the existing impossible-teleport filter.
        overlay.interaction.appendPenContact(InkSample(point: CGPoint(x:40,y:25),pressure:0.5,time:1.1),lifted:true)
        overlay.interaction.appendPenContact(InkSample(point: CGPoint(x:38,y:24),pressure:0,time:1.11),lifted:false)
        overlay.interaction.finishPen(); overlay.commit()
        let stroke = try XCTUnwrap(record.drawing.strokes.first)
        XCTAssertLessThan(PerfectInk.bounds(stroke).maxX,26)
        XCTAssertEqual(stroke.path.last?.location,CGPoint(x:22,y:23))
        XCTAssertEqual(stroke.path.last?.force ?? 0,0.6,accuracy:0.0001)
    }
    func testVisibleOutlineRoundsVerticesWithoutEscapingThePressurePolygon() {
        let vertices = [CGPoint(x:0,y:0),CGPoint(x:20,y:0),CGPoint(x:20,y:10),CGPoint(x:0,y:10)]
        let path = PerfectFreehand.path(from: vertices)
        var curves = 0, lines = 0, closed = false
        path.applyWithBlock { item in
            if item.pointee.type == .addQuadCurveToPoint { curves += 1 }
            if item.pointee.type == .addLineToPoint { lines += 1 }
            if item.pointee.type == .closeSubpath { closed = true }
        }
        XCTAssertEqual(curves,vertices.count); XCTAssertEqual(lines,0); XCTAssertTrue(closed)
        XCTAssertTrue(path.contains(CGPoint(x:10,y:5)))
        XCTAssertFalse(path.contains(CGPoint(x:0.1,y:0.1)),"A sharp pressure-polygon corner is rounded on screen")
        XCTAssertGreaterThanOrEqual(path.boundingBoxOfPath.minX,0)
        XCTAssertLessThanOrEqual(path.boundingBoxOfPath.maxX,20)
    }
}
