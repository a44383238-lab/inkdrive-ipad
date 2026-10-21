import XCTest
import UIKit
import PDFKit
import PencilKit
@testable import InkDriveCore

@MainActor final class EditorInteractionTests: XCTestCase {
    private func editor() throws -> EditorViewController {
        let model = try PDFModel(data: PDFModel.blank(template: .plain))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let editor = EditorViewController(session: EditorSession(model: model, store: CoordinatedStore(url: url), digest: "initial"))
        editor.loadViewIfNeeded()
        editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        editor.view.layoutIfNeeded()
        return editor
    }
    func testPDFAllowsMarkupAndSingleColumnVerticalMovement() throws {
        let editor = try editor()
        XCTAssertTrue(editor.pdfView.isInMarkupMode, "Pencil overlays must receive annotation input")
        XCTAssertEqual(editor.pdfView.displayMode, .singlePageContinuous)
        XCTAssertEqual(editor.pdfView.displayDirection, .vertical)
    }
    func testDrawingGestureIsEnabledAndOnlyPencilDraws() throws {
        let editor = try editor()
        let overlay = PageOverlay(record: editor.session.model.pages[0], editor: editor)
        overlay.frame = CGRect(x: 0, y: 0, width: 595, height: 842)
        overlay.layoutIfNeeded()
        XCTAssertTrue(overlay.canvas.drawingGestureRecognizer.isEnabled)
        XCTAssertEqual(overlay.canvas.drawingPolicy, .pencilOnly)
        XCTAssertNotNil(overlay.canvas.hitTest(CGPoint(x: 30, y: 30), with: nil))
    }
    func testOnlyRequestedToolsRemainAvailable() {
        XCTAssertEqual(Set(EditorTool.allCases.map(\.rawValue)), Set(["pen", "pencil", "marker", "eraser", "lasso", "text"]))
    }
    func testReleaseVelocityDoesNotMoveThePaperAfterFingerLift() {
        let scroll = UIScrollView(); scroll.contentOffset = CGPoint(x: 0, y: 126)
        let proxy = StationaryScrollDelegate(original: nil)
        var predicted = CGPoint(x: 0, y: 500)
        proxy.scrollViewWillEndDragging(scroll, withVelocity: CGPoint(x: 0, y: 7), targetContentOffset: &predicted)
        XCTAssertEqual(predicted, CGPoint(x: 0, y: 126))
    }
    func testFingerCanStartPanningWithoutClaimingPencilInput() {
        let scroll = UIScrollView()
        let viewport = NotebookViewport(); viewport.configure(scroll)
        XCTAssertTrue(scroll.canCancelContentTouches)
        XCTAssertEqual(scroll.panGestureRecognizer.allowedTouchTypes, [NSNumber(value: UITouch.TouchType.direct.rawValue)])
        XCTAssertFalse(scroll.bounces)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    func testCompactToolbarHasMatchingIconsAndVisibleRecordButton() throws {
        let editor = try editor()
        let buttons = descendants(editor.view).compactMap { $0 as? UIButton }
        let pen = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "펜" })
        XCTAssertNotNil(pen.image(for: .normal))
        let recordButton = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "녹음 시작" })
        XCTAssertLessThanOrEqual(recordButton.frame.width, 120)
        XCTAssertNotNil(buttons.first { $0.accessibilityLabel == "서재로" })
        let bar = try XCTUnwrap(pen.superview?.superview?.superview?.superview)
        XCTAssertEqual(bar.frame.height, 48, accuracy: 0.1)
        let image = UIGraphicsImageRenderer(bounds: editor.view.bounds).image { editor.view.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "InkDrive editor landscape"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testToolbarRotationPreservesToolAndClampsInsideViewport() throws {
        UserDefaults.standard.set(false, forKey: "inkdrive.toolbar-vertical")
        let editor = try editor()
        let bar = try XCTUnwrap(descendants(editor.view).first { $0.accessibilityIdentifier == "ink-toolbar" })
        editor.perform(NSSelectorFromString("rotateToolbar")); editor.view.layoutIfNeeded()
        XCTAssertEqual(bar.frame.width, 48, accuracy: 0.1)
        XCTAssertGreaterThan(bar.frame.height, bar.frame.width)
        XCTAssertTrue(editor.view.bounds.contains(bar.frame))
        XCTAssertEqual(editor.tool, .pen)
        editor.perform(NSSelectorFromString("rotateToolbar")); editor.view.layoutIfNeeded()
        XCTAssertEqual(bar.frame.height, 48, accuracy: 0.1)
    }
    func testYellowPaperKeepsVectorPageAndSurvivesSerialization() throws {
        let model = try PDFModel(data: PDFModel.blank(template: .yellowRuled))
        XCTAssertEqual(model.pdf.pageCount, 1)
        XCTAssertEqual(model.pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
        let reopened = try PDFModel(data: model.snapshot())
        XCTAssertEqual(reopened.pages[0].id, model.pages[0].id)
        XCTAssertNotNil(PenNibArtwork.image(tool: .pen, color: .red, width: 0.5))
    }
    func testPagePreviewIncludesUnsavedInkWithoutMutatingPDF() throws {
        let editor = try editor(), record = editor.session.model.pages[0]
        let before = NotebookPreview.image(record, size: CGSize(width: 120, height: 160)).pngData()
        let points = [CGPoint(x: 40, y: 60), CGPoint(x: 150, y: 130)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.2, size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        record.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        let annotationCount = record.page.annotations.count
        XCTAssertNotEqual(NotebookPreview.image(record, size: CGSize(width: 120, height: 160)).pngData(), before)
        XCTAssertEqual(record.page.annotations.count, annotationCount)
    }
    func testToolSettingsUsePixelUnits() {
        let controller = ToolPopoverController(tool: .pen, settings: ToolSettings()) { _ in }
        controller.loadViewIfNeeded()
        XCTAssertTrue(descendants(controller.view).compactMap { ($0 as? UILabel)?.text }.contains("3.0 px"))
    }
    func testLegacyToolSettingsSurviveTextStyleExtension() throws {
        let original = ToolSettings()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "textTraits")
        var restored = try JSONDecoder().decode(ToolSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.color, original.color)
        restored.textTraits = UIFontDescriptor.SymbolicTraits.traitBold.rawValue
        XCTAssertTrue(restored.uiFont.fontDescriptor.symbolicTraits.contains(.traitBold))
    }
    func testRecordButtonStartsWithoutSeparateLessonForm() async throws {
        let editor = try editor(); editor.canRecord = true
        let invoked = expectation(description: "one tap starts recording")
        var calls = 0; editor.recordingAction = { calls += 1; invoked.fulfill() }
        let button = try XCTUnwrap(descendants(editor.view).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "녹음 시작" })
        XCTAssertEqual(button.actions(forTarget: editor, forControlEvent: .touchUpInside), ["toggleRecording"])
        // A Swift-package XCTest host has no UIApplication event dispatcher. Verify the binding above, then invoke its action.
        editor.toggleRecording()
        await fulfillment(of: [invoked], timeout: 3)
        XCTAssertEqual(calls, 1)
    }
}
