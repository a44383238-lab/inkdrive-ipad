import XCTest
import PDFKit
import PencilKit
@testable import InkDriveCore

final class PDFModelTests: XCTestCase {
    func fixture() throws -> PDFDocument {
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { c in
            c.beginPage()
            ("Original text" as NSString).draw(at: CGPoint(x: 50, y: 60), withAttributes: nil)
        }
        return try XCTUnwrap(PDFDocument(data: data))
    }
    func drawing() -> PKDrawing {
        let points = [CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 130)].enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: Double(i), size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }
    func testDrawingRoundTripKeepsOriginalAnnotationsAndDoesNotDuplicateInk() throws {
        let pdf = try fixture()
        let original = PDFAnnotation(bounds: CGRect(x: 50, y: 100, width: 80, height: 30), forType: .freeText, withProperties: nil)
        original.contents = "external annotation"
        pdf.page(at: 0)!.addAnnotation(original)
        let model = try PDFModel(data: XCTUnwrap(pdf.dataRepresentation()))
        model.pages[0].drawing = drawing()
        for _ in 0..<3 {
            let reopened = try PDFModel(data: model.snapshot())
            XCTAssertEqual(reopened.pages[0].drawing.strokes.count, 1)
            XCTAssertEqual(reopened.pages[0].page.annotations.filter { $0.contents == "external annotation" }.count, 1)
            let stored = try XCTUnwrap(PDFDocument(data: reopened.snapshot()))
            XCTAssertEqual(stored.page(at: 0)!.annotations.filter(InkAnnotation.owns).count, 1)
        }
    }
    func testCropOriginAndRotationSurviveSerialization() throws {
        let pdf = try fixture()
        pdf.page(at: 0)!.setBounds(CGRect(x: 10, y: 20, width: 500, height: 700), for: .cropBox)
        pdf.page(at: 0)!.rotation = 90
        let model = try PDFModel(data: XCTUnwrap(pdf.dataRepresentation()))
        model.pages[0].drawing = drawing()
        let reopened = try PDFModel(data: model.snapshot())
        XCTAssertEqual(reopened.pages[0].page.rotation, 90)
        XCTAssertEqual(reopened.pages[0].page.bounds(for: .cropBox), CGRect(x: 10, y: 20, width: 500, height: 700))
        XCTAssertEqual(reopened.pages[0].drawing.strokes.first!.path.first!.location.x, 20, accuracy: 0.01)
    }
    func testPageIdentityFollowsMoveAndLastPageCannotBeDeleted() throws {
        let model = try PDFModel(data: XCTUnwrap(fixture().dataRepresentation()))
        XCTAssertThrowsError(try model.removePage(at: 0))
        let first = model.pages[0].id
        let inserted = try model.insertBlank(at: 1, template: .grid)
        try model.movePage(from: 0, to: 1)
        XCTAssertEqual(model.pages.map(\.id), [inserted.id, first])
        let removed = try model.removePage(at: 0)
        try model.insert(removed, at: 0)
        XCTAssertEqual(model.pages[0].id, inserted.id)
    }
    func testEraseAllInkRemovesAppStampWithoutRemovingExternalText() throws {
        let model = try PDFModel(data: XCTUnwrap(fixture().dataRepresentation()))
        model.pages[0].drawing = drawing()
        let reopened = try PDFModel(data: model.snapshot())
        reopened.pages[0].drawing = PKDrawing()
        let saved = try XCTUnwrap(PDFDocument(data: reopened.snapshot()))
        XCTAssertTrue(saved.page(at: 0)!.annotations.filter(InkAnnotation.owns).isEmpty)
        XCTAssertTrue(saved.string!.contains("Original text"))
    }
    func testInvalidOrLockedPDFDoesNotBecomeAnEmptyNote() {
        XCTAssertThrowsError(try PDFModel(data: Data("not pdf".utf8)))
    }
}
