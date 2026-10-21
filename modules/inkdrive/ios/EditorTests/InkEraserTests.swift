import XCTest
import PencilKit
import UIKit
@testable import InkDriveCore

@MainActor final class InkEraserTests: XCTestCase {
    private func stroke(_ type: PKInk.InkType = .monoline, transform: CGAffineTransform = .identity) -> PKStroke {
        let points = [CGPoint(x: 20, y: 50), CGPoint(x: 180, y: 50)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.2, size: CGSize(width: 8, height: 8), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(type, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()), transform: transform)
    }
    func testWholeStrokeEraserHitsBetweenSamplesAndHonorsToolTarget() {
        let ink = PKDrawing(strokes: [stroke(), stroke(.marker)])
        let result = InkEraser.erase(ink, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50), width: 20, partial: false, target: "marker")
        XCTAssertEqual(result.strokes.count, 1)
        XCTAssertEqual(result.strokes[0].ink.inkType, .monoline)
        let missed = InkEraser.erase(result, from: CGPoint(x: 100, y: 90), to: CGPoint(x: 100, y: 90), width: 20, partial: false, target: "all")
        XCTAssertEqual(missed.strokes.count, 1)
    }
    func testPartialEraserClipsOnlyItsCircleAndSurvivesArchive() throws {
        let ink = PKDrawing(strokes: [stroke()])
        let result = InkEraser.erase(ink, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50), width: 20, partial: true, target: "all")
        let restored = try PKDrawing(data: result.dataRepresentation())
        let mask = try XCTUnwrap(restored.strokes.first?.mask)
        XCTAssertFalse(mask.contains(CGPoint(x: 100, y: 50)))
        XCTAssertTrue(mask.contains(CGPoint(x: 30, y: 50)))
        let twice = InkEraser.erase(restored, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50), width: 20, partial: true, target: "all")
        XCTAssertFalse(try XCTUnwrap(twice.strokes.first?.mask).contains(CGPoint(x: 100, y: 50)))
    }
    func testTransformedStrokeUsesPageCoordinates() {
        let ink = PKDrawing(strokes: [stroke(transform: CGAffineTransform(translationX: 0, y: 80))])
        let result = InkEraser.erase(ink, from: CGPoint(x: 100, y: 130), to: CGPoint(x: 100, y: 130), width: 20, partial: false, target: "all")
        XCTAssertTrue(result.strokes.isEmpty)
    }
    func testMonolineExportsAndArchivePreservesSolidAppearanceAndSamples() throws {
        let drawing = PKDrawing(strokes: [stroke()])
        let exported = try PortableInkExporter.document(drawing: drawing, documentID: UUID(), pageID: UUID(), strokeIDs: [UUID()], sourceSHA256: String(repeating: "a", count: 64), crop: CGRect(x: 0, y: 0, width: 595, height: 842), rotation: 0, revision: 1, createdAt: Date())
        XCTAssertEqual(exported.pages.first?.strokes.first?.tool, "pen")
        let restored = try PKDrawing(data: drawing.dataRepresentation())
        // PencilKit may canonicalize a synthetic constant-width stroke's archive ink name.
        // Verify the stored visual result and samples, rather than the implementation label.
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(drawing.image(from: rect, scale: 2).pngData(), restored.image(from: rect, scale: 2).pngData())
        XCTAssertEqual(restored.strokes.count, 1)
        XCTAssertEqual(restored.strokes[0].ink.color.hexString, "#000000")
        XCTAssertEqual(restored.strokes[0].ink.color.cgColor.alpha, 1)
        XCTAssertTrue(restored.strokes[0].path.allSatisfy { abs($0.opacity - 1) < 0.001 && abs($0.size.width - 8) < 0.001 })
    }
}
