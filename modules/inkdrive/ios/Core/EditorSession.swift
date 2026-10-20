import UIKit
import PDFKit
import PencilKit

@MainActor final class EditorSession {
    private(set) var model: PDFModel
    let store: any PDFStorage
    let history = UndoManager()
    private var digest: String
    private var revision = 0
    private var savedRevision = 0
    private var delayedSave: Task<Void, Never>?
    private var saving: Task<Void, Error>?
    private(set) var blocked = false
    var didChange: (() -> Void)?
    var statusChanged: ((String) -> Void)?
    var dirty: Bool { revision != savedRevision }

    init(model: PDFModel, store: any PDFStorage, digest: String) {
        self.model = model; self.store = store; self.digest = digest
        history.groupsByEvent = false
        history.levelsOfUndo = 80
    }
    static func open(_ url: URL, scope: SecurityScope? = nil) async throws -> EditorSession {
        let store = CoordinatedStore(url: url, scope: scope)
        let snapshot = try await store.read()
        return try EditorSession(model: PDFModel(data: snapshot.data), store: store, digest: snapshot.digest)
    }
    func changeDrawing(pageID: UUID, to new: PKDrawing) {
        guard let record = model.pages.first(where: { $0.id == pageID }) else { return }
        let old = record.drawing
        guard old.dataRepresentation() != new.dataRepresentation() else { return }
        record.drawing = new
        undoable { $0.changeDrawing(pageID: pageID, to: old) }
        changed()
    }
    func insertPage(at index: Int, template: PaperTemplate) throws {
        let page = try model.insertBlank(at: index, template: template)
        undoable { try? $0.deletePage(id: page.id) }
        changed()
    }
    func deletePage(id: UUID) throws {
        guard let index = model.pages.firstIndex(where: { $0.id == id }) else { throw InkError.invalidPage }
        let page = try model.removePage(at: index)
        undoable { $0.restorePage(page, at: index) }
        changed()
    }
    private func restorePage(_ page: NotebookPage, at index: Int) {
        do {
            try model.insert(page, at: index)
            undoable { try? $0.deletePage(id: page.id) }
            changed()
        } catch { statusChanged?(error.localizedDescription) }
    }
    func movePage(from: Int, to: Int) throws {
        try model.movePage(from: from, to: to)
        undoable { try? $0.movePage(from: to, to: from) }
        changed()
    }
    func addAnnotation(_ annotation: PDFAnnotation, pageID: UUID) {
        guard let page = model.pages.first(where: { $0.id == pageID })?.page else { return }
        page.addAnnotation(annotation)
        undoable { $0.removeAnnotation(annotation, pageID: pageID) }
        changed()
    }
    func removeAnnotation(_ annotation: PDFAnnotation, pageID: UUID) {
        guard let page = model.pages.first(where: { $0.id == pageID })?.page else { return }
        page.removeAnnotation(annotation)
        undoable { $0.addAnnotation(annotation, pageID: pageID) }
        changed()
    }
    func replaceAnnotation(_ old: PDFAnnotation, with new: PDFAnnotation, pageID: UUID) {
        guard let page = model.pages.first(where: { $0.id == pageID })?.page else { return }
        page.removeAnnotation(old); page.addAnnotation(new)
        undoable { $0.replaceAnnotation(new, with: old, pageID: pageID) }
        changed()
    }
    private func undoable(_ action: @escaping (EditorSession) -> Void) {
        if history.isUndoing || history.isRedoing {
            history.registerUndo(withTarget: self, handler: action)
        } else if history.groupingLevel > 0 {
            history.registerUndo(withTarget: self, handler: action)
        } else {
            history.beginUndoGrouping(); history.registerUndo(withTarget: self, handler: action); history.endUndoGrouping()
        }
    }
    private func changed() {
        revision += 1; didChange?()
        guard !blocked else { return }
        statusChanged?("저장 대기 중")
        delayedSave?.cancel()
        delayedSave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 900_000_000) } catch { return }
            guard let self else { return }
            do { try await self.flush() } catch { self.statusChanged?(error.localizedDescription) }
        }
    }
    /// Waiters share the entire save loop, so close never races a prior write.
    func flush() async throws {
        if let saving { return try await saving.value }
        guard !blocked else { throw InkError.conflict }
        let task = Task { @MainActor in
            while self.dirty {
                let targetRevision = self.revision
                let bytes = try self.model.snapshot()
                self.statusChanged?("원본 저장 중…")
                do {
                    self.digest = try await self.store.write(bytes, expected: self.digest)
                    self.savedRevision = targetRevision
                } catch {
                    if let ink = error as? InkError, case .conflict = ink { self.blocked = true }
                    throw error
                }
            }
            self.statusChanged?("원본 저장됨 · iCloud 동기화 대기 가능")
        }
        saving = task
        defer { saving = nil }
        try await task.value
    }
    func checkExternalChange() async throws {
        guard saving == nil else { return }
        let beforeRevision = revision, beforeDigest = digest
        let current = try await store.read()
        guard saving == nil, revision == beforeRevision, digest == beforeDigest else { return }
        guard current.digest != digest else { return }
        if dirty { blocked = true; throw InkError.conflict }
        try replaceFromDisk(current)
    }
    func reloadDiscardingChanges() async throws {
        guard saving == nil else { throw InkError.busy }
        delayedSave?.cancel()
        let beforeRevision = revision
        let current = try await store.read()
        guard revision == beforeRevision, saving == nil else { throw InkError.busy }
        try replaceFromDisk(current)
    }
    private func replaceFromDisk(_ snapshot: FileSnapshot) throws {
        let replacement = try PDFModel(data: snapshot.data)
        model = replacement; digest = snapshot.digest; revision = 0; savedRevision = 0; blocked = false
        history.removeAllActions(); didChange?(); statusChanged?("외부 버전을 다시 열었어요")
    }
}
