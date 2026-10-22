import Foundation
import PencilKit

/// PKDrawing may canonicalize constant-pressure carriers to another ink type.
/// Explicit ownership is therefore part of the app archive, never inferred from visual ink alone on decode.
struct NativeInkArchive: Codable {
    let version: Int
    let drawing: Data
    let perfect: [Int]
    init(_ drawing: PKDrawing) {
        perfect = drawing.strokes.indices.filter { PerfectInk.owns(drawing.strokes[$0]) }
        version = 1; self.drawing = drawing.dataRepresentation()
    }
    func decode() throws -> PKDrawing {
        guard version == 1 else { throw InkError.corruptInk }
        return try Self.restore(PKDrawing(data: drawing), perfect: perfect)
    }
    static func restore(_ drawing: PKDrawing, perfect: [Int]) throws -> PKDrawing {
        guard Set(perfect).count == perfect.count, perfect.allSatisfy({ drawing.strokes.indices.contains($0) && drawing.strokes[$0].mask != nil }) else { throw InkError.corruptInk }
        let indices = Set(perfect)
        return PKDrawing(strokes: drawing.strokes.enumerated().map { index, stroke in
            guard indices.contains(index) else { return stroke }
            return PKStroke(ink: PKInk(.fountainPen,color: stroke.ink.color.withAlphaComponent(1)),path: stroke.path,transform: stroke.transform,mask: stroke.mask)
        })
    }
}
