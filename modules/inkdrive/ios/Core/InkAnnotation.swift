import PDFKit
import PencilKit

/// PDFKit records draw(with:in:) as a portable appearance stream during serialization.
final class InkAnnotation: PDFAnnotation {
    static let ownerKey = PDFAnnotationKey(rawValue: "InkDriveOwner")
    static let dataKey = PDFAnnotationKey(rawValue: "InkDriveDrawingV1")
    static let perfectKey = PDFAnnotationKey(rawValue: "InkDrivePerfectInkV1")
    static let owner = "inkdrive.pencil.v1"
    private let drawing: PKDrawing
    private let crop: CGRect

    init(drawing: PKDrawing, crop: CGRect) {
        self.drawing = drawing; self.crop = crop
        super.init(bounds: crop, forType: .stamp, withProperties: nil)
        shouldDisplay = true; shouldPrint = true
        setValue(Self.owner, forAnnotationKey: Self.ownerKey)
        let indices = drawing.strokes.indices.filter { PerfectInk.owns(drawing.strokes[$0]) }
        setValue(drawing.dataRepresentation().base64EncodedString(), forAnnotationKey: Self.dataKey)
        if !indices.isEmpty, let bytes = try? JSONEncoder().encode(indices), let text = String(data: bytes, encoding: .utf8) { setValue(text, forAnnotationKey: Self.perfectKey) }
    }
    required init?(coder: NSCoder) { fatalError("Use PDFModel to restore drawing data") }
    static func owns(_ annotation: PDFAnnotation) -> Bool {
        annotation.value(forAnnotationKey: ownerKey) as? String == owner
    }
    static func decode(_ annotation: PDFAnnotation) throws -> PKDrawing {
        guard let encoded = annotation.value(forAnnotationKey: dataKey) as? String,
              encoded.utf8.count <= 90_000_000, let bytes = Data(base64Encoded: encoded)
        else { throw InkError.corruptInk }
        do {
            let drawing = try PKDrawing(data: bytes)
            guard let text = annotation.value(forAnnotationKey: perfectKey) as? String else { return drawing }
            guard text.utf8.count <= 2_000_000, let data = text.data(using: .utf8) else { throw InkError.corruptInk }
            return try NativeInkArchive.restore(drawing, perfect: JSONDecoder().decode([Int].self,from: data))
        } catch { throw InkError.corruptInk }
    }
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        context.clip(to: crop)
        context.translateBy(x: crop.minX, y: crop.maxY)
        context.scaleBy(x: 1, y: -1)
        VectorInkPainter.draw(drawing, in: context)
        context.restoreGState()
    }
}
