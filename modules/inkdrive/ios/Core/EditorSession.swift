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
    private var journal: InkJournal?
    private var commits: InkCommitStore?
    private(set) var blocked = false
    var didChange: (() -> Void)?
    private(set) var changedDrawingPageID: UUID?
    private var activeInkPages = Set<UUID>()
    func beginInkInput(_ pageID: UUID) { activeInkPages.insert(pageID); delayedSave?.cancel() }
    func endInkInput(_ pageID: UUID) {
        let removed = activeInkPages.remove(pageID)
        if removed != nil, activeInkPages.isEmpty, dirty { scheduleSave() }
    }
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
        let journal = try InkJournal(documentURL: url)
        let recovery = try journal.read()
        if let recovery, recovery.expected != snapshot.digest {
            // Preserve a conflicting recovery separately before this path is used for a new journal.
            let backup = journal.file.deletingLastPathComponent().appendingPathComponent("conflict-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: journal.file, to: backup)
        }
        let recovered = recovery?.expected == snapshot.digest ? recovery?.pdf : nil
        let adapterURL = URL(fileURLWithPath: url.path + ".adapter.json")
        let adapter = FileManager.default.fileExists(atPath: adapterURL.path) ? try JSONDecoder().decode(DocumentAdapter.self, from: Data(contentsOf: adapterURL)) : nil
        let session = try EditorSession(model: PDFModel(data: recovered ?? snapshot.data, documentID: adapter?.documentID, pageIDs: adapter?.pageIDs), store: store, digest: snapshot.digest)
        session.journal = journal
        if let root = scope?.url, (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let originals = root.appendingPathComponent(".inkdrive/originals/\(session.model.documentID.uuidString.lowercased())")
            try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
            let original = originals.appendingPathComponent(snapshot.digest + ".pdf")
            if !FileManager.default.fileExists(atPath: original.path) { try snapshot.data.write(to: original, options: .withoutOverwriting) }
            session.commits = try InkCommitStore(root: root, documentID: session.model.documentID, documentURL: url)
            if session.model.needsIdentityPersistence { session.preservePageIdentities() }
        }
        if recovered != nil { session.preservePageIdentities() }
        return session
    }
    func changeDrawing(pageID: UUID, to new: PKDrawing, alreadyCompared: Bool = false) {
        guard let record = model.pages.first(where: { $0.id == pageID }) else { return }
        let old = record.drawing
        guard alreadyCompared || old.dataRepresentation() != new.dataRepresentation() else { return }
        record.drawing = new
        undoable { $0.changeDrawing(pageID: pageID, to: old) }
        changedDrawingPageID = pageID; defer { changedDrawingPageID = nil }
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
        scheduleSave()
    }
    private func scheduleSave() {
        delayedSave?.cancel()
        guard activeInkPages.isEmpty, !blocked else { return }
        delayedSave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            guard let self else { return }
            do { try await self.flush() } catch { self.statusChanged?(error.localizedDescription) }
        }
    }
    func preservePageIdentities() { changed() }
    /// Waiters share the entire save loop, so close never races a prior write.
    func flush() async throws {
        if let saving { return try await saving.value }
        guard !blocked else { throw InkError.conflict }
        let task = Task { @MainActor in
            while self.dirty {
                guard self.activeInkPages.isEmpty else { return }
                let targetRevision = self.revision
                let snapshot = try self.model.snapshotJob()
                let bytes = try await Task.detached(priority: .utility) { try snapshot.render() }.value
                try self.journal?.write(bytes, expected: self.digest)
                self.statusChanged?("원본 저장 중…")
                do {
                    try self.commits?.checkHead()
                    self.digest = try await self.store.write(bytes, expected: self.digest)
                    self.savedRevision = targetRevision
                    // Keep recovery until both normal PDF and the independent commit are durable.
                    try self.journal?.write(bytes, expected: self.digest)
                    try self.commits?.publish(PDFModel(data: bytes), fileBytes: bytes)
                    if self.revision == targetRevision { try self.journal?.clear() }
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
        if let commits { self.commits = try InkCommitStore(root: commits.libraryRoot, documentID: replacement.documentID, documentURL: commits.documentURL) }
        model = replacement; digest = snapshot.digest; revision = 0; savedRevision = 0; blocked = false
        history.removeAllActions(); didChange?(); statusChanged?("외부 버전을 다시 열었어요")
    }
}
