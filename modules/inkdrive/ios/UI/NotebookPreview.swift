import UIKit
import PDFKit

@MainActor enum NotebookPreview {
    static func image(_ record: NotebookPage, size: CGSize) -> UIImage {
        guard let copy = record.page.copy() as? PDFPage else { return record.page.thumbnail(of: size, for: .cropBox) }
        if !record.drawing.strokes.isEmpty {
            copy.addAnnotation(InkAnnotation(drawing: record.drawing, crop: copy.bounds(for: .cropBox)))
        }
        return copy.thumbnail(of: size, for: .cropBox)
    }
}
