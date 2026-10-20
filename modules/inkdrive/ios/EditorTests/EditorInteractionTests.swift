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
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    func testCompactToolbarHasMatchingIconsAndVisibleRecordButton() throws {
        let editor = try editor()
        let buttons = descendants(editor.view).compactMap { $0 as? UIButton }
        let pen = try XCTUnwrap(buttons.first { $0.accessibilityLabel == "펜" })
        XCTAssertNotNil(pen.image(for: .normal))
        XCTAssertNotNil(buttons.first { $0.accessibilityLabel == "녹음 시작" })
        XCTAssertNotNil(buttons.first { $0.accessibilityLabel == "서재로" })
        let bar = try XCTUnwrap(pen.superview?.superview?.superview?.superview)
        XCTAssertEqual(bar.frame.height, 56, accuracy: 0.1)
        let image = UIGraphicsImageRenderer(bounds: editor.view.bounds).image { editor.view.layer.render(in: $0.cgContext) }
        let attachment = XCTAttachment(image: image); attachment.name = "InkDrive editor landscape"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testToolSettingsUsePixelUnits() {
        let controller = ToolPopoverController(tool: .pen, settings: ToolSettings()) { _ in }
        controller.loadViewIfNeeded()
        XCTAssertTrue(descendants(controller.view).compactMap { ($0 as? UILabel)?.text }.contains("3.0 px"))
    }
    func testRecordButtonStartsWithoutSeparateLessonForm() async throws {
        let editor = try editor(); editor.canRecord = true
        let invoked = expectation(description: "one tap starts recording")
        var calls = 0; editor.recordingAction = { calls += 1; invoked.fulfill() }
        let button = try XCTUnwrap(descendants(editor.view).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "녹음 시작" })
        button.sendActions(for: .touchUpInside)
        await fulfillment(of: [invoked], timeout: 3)
        XCTAssertEqual(calls, 1)
    }
}
