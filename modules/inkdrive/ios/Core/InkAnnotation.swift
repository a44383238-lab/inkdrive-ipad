import PDFKit
import PencilKit

/// PDFKit records draw(with:in:) as a portable appearance stream during serialization.
final class InkAnnotation: PDFAnnotation {
    static let ownerKey = PDFAnnotationKey(rawValue: "InkDriveOwner")
    static let dataKey = PDFAnnotationKey(rawValue: "InkDriveDrawingV1")
    static let owner = "inkdrive.pencil.v1"
    private let drawing: PKDrawing
    private let crop: CGRect

    init(drawing: PKDrawing, crop: CGRect) {
        self.drawing = drawing; self.crop = crop
        super.init(bounds: crop, forType: .stamp, withProperties: nil)
        shouldDisplay = true; shouldPrint = true
        setValue(Self.owner, forAnnotationKey: Self.ownerKey)
        setValue(drawing.dataRepresentation().base64EncodedString(), forAnnotationKey: Self.dataKey)
    }
    required init?(coder: NSCoder) { fatalError("Use PDFModel to restore drawing data") }
    static func owns(_ annotation: PDFAnnotation) -> Bool {
        annotation.value(forAnnotationKey: ownerKey) as? String == owner
    }
    static func decode(_ annotation: PDFAnnotation) throws -> PKDrawing {
        guard let encoded = annotation.value(forAnnotationKey: dataKey) as? String,
              encoded.utf8.count <= 90_000_000, let bytes = Data(base64Encoded: encoded)
        else { throw InkError.corruptInk }
        do { return try PKDrawing(data: bytes) } catch { throw InkError.corruptInk }
    }
    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let canvasRect = CGRect(origin: .zero, size: crop.size)
        let area = max(1, crop.width * crop.height)
        let scale = min(2, sqrt(16_000_000 / area))
        let image = drawing.image(from: canvasRect, scale: scale)
        context.saveGState()
        context.clip(to: crop)
        context.translateBy(x: crop.minX, y: crop.maxY)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        image.draw(in: canvasRect)
        UIGraphicsPopContext()
        context.restoreGState()
    }
}
