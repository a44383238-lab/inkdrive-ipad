import Foundation
import PencilKit
import UIKit
import CryptoKit

// Lossless sample metadata and vector clipping, alongside the original editable PKDrawing.
struct PortableInkDocument: Codable {
    let format: String
    let version: Int
    let documentId: String
    let sourceRevision: String
    let inkRevision: Int
    let createdAt: String
    let updatedAt: String
    let layers: [PortableInkLayer]
    let pages: [PortableInkPage]
    var previewRevision: String? = nil
}
struct PortableInkLayer: Codable { let id: String; let name: String; let visible: Bool }
struct PortableInkBounds: Codable { let x: Double; let y: Double; let width: Double; let height: Double }
struct PortableInkPage: Codable {
    let id: String; let kind: String; let unit: String; let bounds: PortableInkBounds; let rotation: Int
    let strokes: [PortableInkStroke]
}
struct PortableInkStroke: Codable {
    let id: String; let layerId: String; let tool: String; let color: String; let opacity: Double
    let createdAt: String; let updatedAt: String; let transform: [Double]; let samples: [PortableInkSample]
    var mask: [[Double]]? = nil
    var maskEvenOdd: Bool? = nil
    var outline: [[Double]]? = nil
}
struct PortableInkSample: Codable {
    let x: Double; let y: Double; let width: Double; let height: Double
    let pressure: Double; let opacity: Double; let timeMs: Double
}
enum PortableInkError: Error { case identity, bounds, unsupportedMask, unsupportedTool, unsupportedColor, sampleBudget, sample }

enum PortableInkExporter {
    static func document(drawing: PKDrawing, documentID: UUID, pageID: UUID, strokeIDs: [UUID], sourceSHA256: String,
                         crop: CGRect, rotation: Int, revision: Int, createdAt: Date, now: Date = Date()) throws -> PortableInkDocument {
        guard sourceSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              revision > 0, strokeIDs.count == drawing.strokes.count, Set(strokeIDs).count == strokeIDs.count,
              now >= createdAt else { throw PortableInkError.identity }
        guard crop.width > 0, crop.height > 0, [crop.minX, crop.minY, crop.width, crop.height].allSatisfy({ $0.isFinite }),
              [0, 90, 180, 270].contains(rotation) else { throw PortableInkError.bounds }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var count = 0
        var strokes: [PortableInkStroke] = []
        for (index, stroke) in drawing.strokes.enumerated() {
            // Preserve the pretransform eraser clipping path as document-coordinate commands.
            let tool: String
            switch stroke.ink.inkType {
            case .pen, .monoline, .fountainPen: tool = "pen"
            case .pencil: tool = "pencil"
            case .marker: tool = "marker"
            default: throw PortableInkError.unsupportedTool
            }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            guard stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &alpha)
            else { throw PortableInkError.unsupportedColor }
            let color = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
            let t = stroke.transform
            // F * strokeTransform * F^-1, where F maps canvas top-left into actual PDF crop user-space.
            let tx: CGFloat = crop.minX + t.tx - t.a * crop.minX + t.c * crop.maxY
            let ty: CGFloat = crop.maxY - t.ty + t.b * crop.minX - t.d * crop.maxY
            let coefficients: [CGFloat] = [t.a, -t.b, -t.c, t.d, tx, ty]
            let transform: [Double] = coefficients.map { Double($0) }
            let samples: [PortableInkSample] = try stroke.path.interpolatedPoints(by: .distance(0.5)).map { point in
                count += 1; guard count <= 2_000_000 else { throw PortableInkError.sampleBudget }
                let values = [point.location.x, point.location.y, point.size.width, point.size.height, point.force, point.opacity]
                guard values.allSatisfy({ $0.isFinite }), point.size.width > 0, point.size.height > 0,
                      point.force >= 0, point.force <= 10, point.opacity >= 0, (PerfectInk.owns(stroke) || point.opacity <= 1), point.timeOffset.isFinite, point.timeOffset >= 0
                else { throw PortableInkError.sample }
                let width = PerfectInk.owns(stroke) ? PerfectFreehand.radius(size: point.size.width, pressure: point.force) * 2 : point.size.width
                let height = PerfectInk.owns(stroke) ? width : point.size.height
                return PortableInkSample(x: Double(crop.minX + point.location.x), y: Double(crop.maxY - point.location.y),
                    width: Double(width), height: Double(height), pressure: Double(point.force),
                    opacity: PerfectInk.owns(stroke) ? 1 : Double(point.opacity), timeMs: point.timeOffset * 1000)
            }
            guard !samples.isEmpty, samples.count <= 100_000, now >= stroke.path.creationDate else { throw PortableInkError.sample }
            var output = PortableInkStroke(id: strokeIDs[index].uuidString.lowercased(), layerId: "main", tool: tool, color: color,
                opacity: Double(alpha), createdAt: formatter.string(from: stroke.path.creationDate), updatedAt: formatter.string(from: now),
                transform: transform, samples: samples)
            if PerfectInk.owns(stroke) {
                output.outline = PerfectInk.commands(PerfectInk.outline(stroke)) { CGPoint(x: crop.minX + $0.x, y: crop.maxY - $0.y) }
                // The outline is already the visible result, including any partial erasing.
                strokes.append(output); continue
            }
            if let mask = stroke.mask {
                var commands: [[Double]] = []
                mask.cgPath.applyWithBlock { element in
                    let e = element.pointee
                    let type: Int, points: Int
                    switch e.type {
                    case .moveToPoint: type = 0; points = 1
                    case .addLineToPoint: type = 1; points = 1
                    case .addQuadCurveToPoint: type = 2; points = 2
                    case .addCurveToPoint: type = 3; points = 3
                    case .closeSubpath: type = 4; points = 0
                    @unknown default: type = -1; points = 0
                    }
                    var command = [Double(type)]
                    for i in 0..<points { command += [Double(crop.minX + e.points[i].x), Double(crop.maxY - e.points[i].y)] }
                    commands.append(command)
                }
                guard commands.allSatisfy({ $0.first != -1 && $0.allSatisfy(\.isFinite) }) else { throw PortableInkError.unsupportedMask }
                output.mask = commands; output.maskEvenOdd = mask.usesEvenOddFillRule
            }
            strokes.append(output)
        }
        let page = PortableInkPage(id: pageID.uuidString.lowercased(), kind: "pdf", unit: "pt",
            bounds: PortableInkBounds(x: Double(crop.minX), y: Double(crop.minY), width: Double(crop.width), height: Double(crop.height)),
            rotation: rotation, strokes: strokes)
        return PortableInkDocument(format: "inkdrive.ink", version: 1, documentId: documentID.uuidString.lowercased(), sourceRevision: sourceSHA256,
            inkRevision: revision, createdAt: formatter.string(from: createdAt), updatedAt: formatter.string(from: now),
            layers: [PortableInkLayer(id: "main", name: "필기", visible: true)], pages: [page])
    }
    static func stableIDs(_ drawing: PKDrawing, pageID: UUID? = nil) -> [UUID] {
        var seen: [String: Int] = [:]
        return drawing.strokes.map { stroke in
            // Path identity ignores lasso transforms and eraser masks, so move/erase/undo retain the ID.
            var bytes = Data(String(stroke.path.creationDate.timeIntervalSince1970).utf8)
            for point in stroke.path { bytes.append(Data("\(point.location.x),\(point.location.y),\(point.timeOffset);".utf8)) }
            let key = CoordinatedStore.digest(bytes), occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            var hash = Array(SHA256.hash(data: Data("\(pageID?.uuidString ?? "legacy"):\(key):\(occurrence)".utf8)).prefix(16))
            hash[6] = (hash[6] & 0x0f) | 0x50; hash[8] = (hash[8] & 0x3f) | 0x80
            return UUID(uuid: (hash[0],hash[1],hash[2],hash[3],hash[4],hash[5],hash[6],hash[7],hash[8],hash[9],hash[10],hash[11],hash[12],hash[13],hash[14],hash[15]))
        }
    }
}
