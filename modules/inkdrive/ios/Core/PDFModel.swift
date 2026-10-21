import PDFKit
import PencilKit

enum PaperTemplate: String, CaseIterable { case plain, ruled, grid }
final class NotebookPage {
    let id: UUID
    let page: PDFPage
    var drawing: PKDrawing
    init(page: PDFPage, drawing: PKDrawing = PKDrawing(), id: UUID = UUID()) {
        self.id = id; self.page = page; self.drawing = drawing
    }
}

final class PDFModel {
    let pdf: PDFDocument
    let documentID: UUID
    let needsIdentityPersistence: Bool
    private(set) var pages: [NotebookPage]
    init(data: Data, documentID: UUID? = nil, pageIDs: [UUID]? = nil) throws {
        guard let document = PDFDocument(data: data) else { throw InkError.invalidPDF }
        guard !document.isLocked else { throw InkError.locked }
        guard document.pageCount > 0 else { throw InkError.invalidPDF }
        guard document.allowsCommenting, document.allowsDocumentChanges else { throw InkError.readOnly }
        var records: [NotebookPage] = []
        var documentIDs = Set<UUID>()
        var missingPageID = false
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { throw InkError.invalidPDF }
            let crop = page.bounds(for: .cropBox)
            guard crop.width > 0, crop.height > 0, crop.width.isFinite, crop.height.isFinite,
                  crop.width <= 20_000, crop.height <= 20_000 else { throw InkError.invalidPDF }
            for annotation in page.annotations where annotation.widgetFieldType == .signature { throw InkError.signed }
            let owned = page.annotations.filter(InkAnnotation.owns)
            guard owned.count <= 1 else { throw InkError.corruptInk }
            let drawing = try owned.first.map(InkAnnotation.decode) ?? PKDrawing()
            owned.forEach(page.removeAnnotation)
            let identities = page.annotations.filter { $0.userName == "InkDrive.PageID.v1" }
            if identities.first.flatMap({ UUID(uuidString: $0.contents ?? "") }) == nil { missingPageID = true }
            let id = identities.first.flatMap { UUID(uuidString: $0.contents ?? "") } ?? (pageIDs?.indices.contains(index) == true ? pageIDs![index] : UUID())
            identities.forEach(page.removeAnnotation)
            let docs = page.annotations.filter { $0.userName == "InkDrive.DocumentID.v1" }
            for item in docs { if let uuid = UUID(uuidString: item.contents ?? "") { documentIDs.insert(uuid) } }
            docs.forEach(page.removeAnnotation)
            records.append(NotebookPage(page: page, drawing: drawing, id: id))
        }
        guard documentIDs.count <= 1, Set(records.map(\.id)).count == records.count else { throw InkError.corruptInk }
        if let documentID, let embedded = documentIDs.first, documentID != embedded { throw InkError.conflict }
        self.documentID = documentIDs.first ?? documentID ?? UUID()
        self.needsIdentityPersistence = documentIDs.isEmpty || missingPageID
        self.pdf = document; self.pages = records
    }
    func record(for page: PDFPage) -> NotebookPage? { pages.first { $0.page === page } }
    func snapshot(includeInk: Bool = true) throws -> Data {
        guard let base = pdf.dataRepresentation(), let copy = PDFDocument(data: base) else { throw InkError.serialization }
        for (index, record) in pages.enumerated() {
            guard let page = copy.page(at: index) else { throw InkError.serialization }
            let identity = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .text, withProperties: nil)
            identity.userName = "InkDrive.PageID.v1"; identity.contents = record.id.uuidString
            identity.shouldDisplay = false; identity.shouldPrint = false; page.addAnnotation(identity)
            let documentIdentity = PDFAnnotation(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), forType: .text, withProperties: nil)
            documentIdentity.userName = "InkDrive.DocumentID.v1"; documentIdentity.contents = documentID.uuidString
            documentIdentity.shouldDisplay = false; documentIdentity.shouldPrint = false; page.addAnnotation(documentIdentity)
            if includeInk && !record.drawing.strokes.isEmpty { page.addAnnotation(InkAnnotation(drawing: record.drawing, crop: page.bounds(for: .cropBox))) }
        }
        guard let bytes = copy.dataRepresentation(), let check = PDFDocument(data: bytes), check.pageCount == pages.count else {
            throw InkError.serialization
        }
        return bytes
    }
    @discardableResult func insertBlank(at index: Int, template: PaperTemplate) throws -> NotebookPage {
        let data = Self.blank(template: template)
        guard let page = PDFDocument(data: data)?.page(at: 0)?.copy() as? PDFPage else { throw InkError.serialization }
        let record = NotebookPage(page: page)
        try insert(record, at: index)
        return record
    }
    func insert(_ record: NotebookPage, at index: Int) throws {
        guard (0...pages.count).contains(index) else { throw InkError.invalidPage }
        pdf.insert(record.page, at: index); pages.insert(record, at: index)
    }
    @discardableResult func removePage(at index: Int) throws -> NotebookPage {
        guard pages.count > 1 else { throw InkError.lastPage }
        guard pages.indices.contains(index) else { throw InkError.invalidPage }
        pdf.removePage(at: index); return pages.remove(at: index)
    }
    func movePage(from: Int, to: Int) throws {
        guard pages.indices.contains(from), pages.indices.contains(to) else { throw InkError.invalidPage }
        let record = pages.remove(at: from)
        pdf.removePage(at: from); pages.insert(record, at: to); pdf.insert(record.page, at: to)
    }
    static func blank(template: PaperTemplate) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            renderer.beginPage()
            let context = renderer.cgContext
            UIColor.white.setFill(); context.fill(bounds)
            guard template != .plain else { return }
            UIColor(white: 0.87, alpha: 1).setStroke(); context.setLineWidth(0.4)
            for y in stride(from: 36.0, through: 806.0, by: 24) {
                context.move(to: CGPoint(x: 24, y: y)); context.addLine(to: CGPoint(x: 571, y: y))
            }
            if template == .grid {
                for x in stride(from: 24.0, through: 571.0, by: 24) {
                    context.move(to: CGPoint(x: x, y: 36)); context.addLine(to: CGPoint(x: x, y: 806))
                }
            }
            context.strokePath()
        }
    }
}
