import XCTest
import PencilKit
import PDFKit
import UIKit
@testable import InkDriveCore

@MainActor final class PortableInkTests: XCTestCase {
    private func drawing(mask: UIBezierPath? = nil) -> PKDrawing {
        let points = [CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 130)].enumerated().map { i, p in
            PKStrokePoint(location: p, timeOffset: Double(i) * 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 0.7, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: UIColor(red: 0, green: 0, blue: 1, alpha: 0.8)),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 100)),
            transform: CGAffineTransform(translationX: 12, y: -3), mask: mask)])
    }
    func testPDFDocumentCoordinatesPreserveCropTransformAndPressure() throws {
        let strokeID = UUID()
        let doc = try PortableInkExporter.document(drawing: drawing(), documentID: UUID(), pageID: UUID(), strokeIDs: [strokeID],
            sourceSHA256: String(repeating: "a", count: 64), crop: CGRect(x: 10, y: 20, width: 500, height: 700), rotation: 90,
            revision: 1, createdAt: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 200))
        let stroke = try XCTUnwrap(doc.pages.first?.strokes.first)
        XCTAssertEqual(stroke.id, strokeID.uuidString.lowercased())
        XCTAssertEqual(stroke.transform, [1, 0, 0, 1, 12, 3])
        XCTAssertEqual(stroke.samples.first!.x, 30, accuracy: 0.1)
        XCTAssertEqual(stroke.samples.first!.y, 690, accuracy: 0.1)
        XCTAssertEqual(stroke.samples.first!.pressure, 0.7, accuracy: 0.05)
        XCTAssertEqual(stroke.samples.first!.width, 4, accuracy: 0.1)
        XCTAssertEqual(doc.pages.first?.rotation, 90)
        XCTAssertEqual(doc.pages.first?.unit, "pt")
        let encoded = try JSONEncoder().encode(doc)
        let reopened = try JSONDecoder().decode(PortableInkDocument.self, from: encoded)
        XCTAssertEqual(reopened.pages.first?.strokes.first?.id, stroke.id)
    }
    func testMissingIDsAndMaskedStrokesNeverSilentlyBecomeUnmaskedInk() {
        let common: (PKDrawing, [UUID]) throws -> PortableInkDocument = { drawing, ids in
            try PortableInkExporter.document(drawing: drawing, documentID: UUID(), pageID: UUID(), strokeIDs: ids,
                sourceSHA256: String(repeating: "a", count: 64), crop: CGRect(x: 0, y: 0, width: 500, height: 700), rotation: 0,
                revision: 1, createdAt: Date(timeIntervalSince1970: 100), now: Date(timeIntervalSince1970: 200))
        }
        XCTAssertThrowsError(try common(drawing(), []))
        XCTAssertNoThrow(try common(drawing(mask: UIBezierPath(rect: CGRect(x: 0, y: 0, width: 20, height: 20))), [UUID()]))
        let masked = try? common(drawing(mask: UIBezierPath(rect: CGRect(x: 0, y: 0, width: 20, height: 20))), [UUID()])
        XCTAssertEqual(masked?.pages.first?.strokes.first?.mask?.first, [0, 0, 700])
    }
}
