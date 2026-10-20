import XCTest
import UIKit
import PDFKit
import PencilKit
@testable import InkDriveEditor

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
}
