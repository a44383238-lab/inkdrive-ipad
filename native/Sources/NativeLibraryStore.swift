import SwiftUI
import UniformTypeIdentifiers

struct LibraryEntry: Identifiable {
    let name: String
    let path: String
    let directory: Bool
    var id: String { path }
    var displayName: String { directory ? Self.folderTitle(name) : name }
    static func folderTitle(_ name: String) -> String {
        if name.range(of: "^20[0-9]{2}-(0010|0020)$", options: .regularExpression) != nil {
            return String(name.prefix(4)) + " · " + (name.hasSuffix("0010") ? "1학기" : "2학기")
        }
        return name.replacingOccurrences(of: "_[A-Z]{2}[0-9]+_([0-9]{3})$", with: " ($1)", options: .regularExpression)
    }
}
struct OpenDocument: Identifiable { let id = UUID(); let path: String; let externalURL: URL? }
enum LibraryScreen { case library, today, campus, settings }

@MainActor final class NativeLibraryStore: ObservableObject {
    let repository = LibraryRepository()
    lazy var campus = CampusSync(repository: repository)
    @Published var material: MaterialDocument?
    @Published var screen = LibraryScreen.library
    @Published var path = ""
    @Published var entries: [LibraryEntry] = []
    @Published var lessons: [LessonRecord] = []
    @Published var rootName: String?
    @Published var query = ""
    @Published var favorites = Set(UserDefaults.standard.stringArray(forKey: "library.favorites") ?? [])
    @Published var recent = UserDefaults.standard.stringArray(forKey: "library.recent") ?? []
    @Published var folderColors = UserDefaults.standard.dictionary(forKey: "library.folder-colors") as? [String: String] ?? [:]
    @Published var date = NativeLibraryStore.today()
    @Published var busy = false
    @Published var message: String?
    @Published var document: OpenDocument?
    @Published var textPreview: TextPreview?
    @Published var activeRecording = false
    @Published var elapsed = 0.0
    @Published var pendingRecording = false
    private var picker: NativePicker?
    private var timer: Timer?
    private var lastRecordingError: String?
    struct TextPreview: Identifiable { let id = UUID(); let title: String; let text: String }
    static func today() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter.string(from: Date())
    }
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-smoke") {
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("InkDrive-preview-\(UUID().uuidString)/InkDrive", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try repository.choose(folder)
                for subject in ["통계학", "산업데이터과학", "작업설계", "강의자료"] { try repository.createFolder(parent: "", name: subject) }
                _ = try repository.createNote(parent: "통계학", name: "강의 1", template: "ruled")
                _ = try repository.createNote(parent: "통계학", name: "강의 2", template: "grid")
                try Data("<html><meta charset='utf-8'><body style='padding:40px;font-family:sans-serif'><h1>InkDrive HTML</h1><p>Fixed snapshot keeps the original document.</p></body></html>".utf8).write(to: folder.appendingPathComponent("강의자료/스냅샷.html"))
            } catch { message = error.localizedDescription }
        }
        #endif
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
    }
    deinit { timer?.invalidate() }
    var filtered: [LibraryEntry] {
        entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted {
            if $0.directory != $1.directory { return $0.directory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var breadcrumbs: [String] { path.split(separator: "/").map(String.init) }
    var hasRoot: Bool { rootName != nil }
    func refresh() {
        rootName = repository.root?.name
        guard hasRoot else { entries = []; lessons = []; return }
        do {
            entries = try repository.list(path).compactMap { value in
                guard let name = value["name"] as? String, let path = value["path"] as? String, let directory = value["directory"] as? Bool else { return nil }
                return LibraryEntry(name: name, path: path, directory: directory)
            }
            lessons = try repository.lessons(date: date).sorted { ($0.subject, $0.title) < ($1.subject, $1.title) }
            pendingRecording = (try repository.pendingRecording()) != nil
        } catch { message = error.localizedDescription }
        poll()
    }
    private func poll() {
        let service = RecordingService.shared
        let ended = activeRecording && !service.active
        activeRecording = service.active; elapsed = service.seconds
        if let error = service.lastError, error != lastRecordingError { message = error; lastRecordingError = error }
        if ended { refresh() }
    }
    func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do { try await action(); refresh() } catch { message = error.localizedDescription }
        }
    }
    func navigate(_ next: String) {
        do {
            if !next.isEmpty { let scope = try repository.access(); _ = try FileNames.child(next, in: scope.url) }
            path = next; query = ""; refresh()
        } catch { message = error.localizedDescription }
    }
    func parent() { navigate(breadcrumbs.dropLast().joined(separator: "/")) }
    func open(_ entry: LibraryEntry) {
        if !entry.directory {
            recent.removeAll { $0 == entry.path }; recent.insert(entry.path, at: 0)
            recent = Array(recent.prefix(30)); UserDefaults.standard.set(recent, forKey: "library.recent")
        }
        if entry.directory { navigate(entry.path) }
        else if entry.path.lowercased().hasSuffix(".pdf") { document = OpenDocument(path: entry.path, externalURL: nil) }
        else if !["md", "txt", "json", "csv"].contains(URL(fileURLWithPath: entry.path).pathExtension.lowercased()) {
            do {
                let scope = try repository.access(), url = try FileNames.child(entry.path, in: scope.url)
                if url.pathExtension.lowercased() == "pptx" {
                    let hash = try FileHasher.digest(url), folder = scope.url.appendingPathComponent(".inkdrive/previews/\(hash)")
                    let preview = folder.appendingPathComponent("preview.pdf")
                    if let bytes = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                       let metadata = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                       metadata["sourceSHA256"] as? String == hash, let previewHash = metadata["previewSHA256"] as? String,
                       (try? FileHasher.digest(preview)) == previewHash,
                       let width = metadata["widthEMU"] as? Double, let height = metadata["heightEMU"] as? Double {
                        let notebook = folder.appendingPathComponent("notebook.pdf")
                        if !FileManager.default.fileExists(atPath: notebook.path) { try FileManager.default.copyItem(at: preview, to: notebook) }
                        var adapter = DocumentAdapter(kind: "pptx", originalPath: entry.path, originalSHA256: hash, width: width, height: height)
                        adapter.documentID = (metadata["documentId"] as? String).flatMap(UUID.init(uuidString:))
                        adapter.pageIDs = (metadata["pageIDs"] as? [String])?.compactMap(UUID.init(uuidString:))
                        try JSONEncoder().encode(adapter).write(to: URL(fileURLWithPath: notebook.path + ".adapter.json"), options: .atomic)
                        document = OpenDocument(path: ".inkdrive/previews/\(hash)/notebook.pdf", externalURL: nil); return
                    }
                }
                material = MaterialDocument(url: url, scope: scope)
            }
            catch { message = error.localizedDescription }
        } else {
            do { textPreview = TextPreview(title: entry.name, text: try repository.readText(entry.path)) }
            catch { message = error.localizedDescription }
        }
    }
    func create(name: String, folder: Bool, template: PaperTemplate) throws {
        if folder { try repository.createFolder(parent: path, name: name) }
        else { _ = try repository.createNote(parent: path, name: name, template: template.rawValue) }
        refresh()
    }
    func toggleFavorite(_ path: String) {
        if favorites.contains(path) { favorites.remove(path) } else { favorites.insert(path) }
        UserDefaults.standard.set(Array(favorites), forKey: "library.favorites")
    }
    func setFolderColor(_ color: String, path: String) {
        folderColors[path] = color; UserDefaults.standard.set(folderColors, forKey: "library.folder-colors")
    }
    func entry(_ path: String) -> LibraryEntry {
        LibraryEntry(name: URL(fileURLWithPath: path).lastPathComponent, path: path, directory: false)
    }
    func chooseFolder() {
        guard !activeRecording, !pendingRecording else { message = "녹음 종료·복구 후 폴더를 바꿔 주세요."; return }
        run {
            let picker = NativePicker(); self.picker = picker; defer { self.picker = nil }
            guard let url = try await picker.pick(types: [.folder], from: Self.presenter()) else { return }
            try self.repository.choose(url); self.path = ""; self.query = ""
        }
    }
    func choosePDF() {
        run {
            let picker = NativePicker(); self.picker = picker; defer { self.picker = nil }
            guard let url = try await picker.pick(types: [.pdf], from: Self.presenter()) else { return }
            self.document = OpenDocument(path: url.lastPathComponent, externalURL: url)
        }
    }
    func importRecording(_ lesson: LessonRecord) {
        guard !activeRecording else { return }
        run {
            let picker = NativePicker(); self.picker = picker; defer { self.picker = nil }
            guard let url = try await picker.pick(types: [.audio, .mpeg4Movie], from: Self.presenter()) else { return }
            var current = try self.repository.lessons(date: lesson.date).first { $0.id == lesson.id } ?? lesson
            try self.repository.importRecording(url, lesson: &current)
        }
    }
    func finishLesson(_ lesson: LessonRecord) {
        run {
            if RecordingService.shared.active { try await RecordingService.shared.stop() }
            var current = try self.repository.lessons(date: lesson.date).first { $0.id == lesson.id } ?? lesson
            current.endedAt = current.endedAt == nil ? ISO8601DateFormatter().string(from: Date()) : nil
            try self.repository.saveLesson(current)
        }
    }
    func stopRecording() { run { try await RecordingService.shared.stop() } }
    func recoverRecording() { run { try self.repository.recoverPending() } }
    func showRecordings(_ pdf: String, from presenter: UIViewController? = nil) throws {
        let source = try repository.recordings(for: pdf)
        let browser = RecordingBrowserController(rows: source.rows, scope: source.scope)
        if let editor = presenter as? EditorViewController { editor.presentRecordingBrowser(browser); return }
        let navigation = UINavigationController(rootViewController: browser); navigation.modalPresentationStyle = presenter == nil ? .pageSheet : .popover
        navigation.overrideUserInterfaceStyle = .dark
        navigation.preferredContentSize = CGSize(width: 370, height: 420)
        if let presenter {
            navigation.popoverPresentationController?.sourceView = presenter.view
            navigation.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.width - 110, y: presenter.view.safeAreaInsets.top + 38, width: 44, height: 1)
            navigation.popoverPresentationController?.delegate = presenter as? UIPopoverPresentationControllerDelegate
        }
        navigation.sheetPresentationController?.detents = [.medium(), .large()]; navigation.sheetPresentationController?.prefersGrabberVisible = true
        let target = try presenter ?? Self.presenter()
        guard target.presentedViewController == nil else { throw InkError.busy }
        target.present(navigation, animated: true)
    }
    static func presenter() throws -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
        guard var controller = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { throw InkError.unavailable }
        while let next = controller.presentedViewController { controller = next }
        return controller
    }
}

extension LibraryRepository {
    func recoverPending() throws { try RecordingService.shared.recover(repository: self) }
}
