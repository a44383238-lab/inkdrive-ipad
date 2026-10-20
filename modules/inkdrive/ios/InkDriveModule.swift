import ExpoModulesCore
import UniformTypeIdentifiers
import UIKit

public final class InkDriveModule: Module {
    private var repository: LibraryRepository?
    private var picker: NativePicker?
    private var editor: EditorViewController?
    @MainActor private func library() -> LibraryRepository {
        if let repository { return repository }
        let value = LibraryRepository(); repository = value; return value
    }
    @MainActor private func controller() throws -> UIViewController {
        guard let controller = appContext?.utilities?.currentViewController() else { throw InkError.unavailable }
        return controller
    }
    @MainActor private func choose(_ types: [UTType]) async throws -> URL? {
        guard picker == nil, editor == nil else { throw InkError.busy }
        let picker = NativePicker(); self.picker = picker
        defer { self.picker = nil }
        return try await picker.pick(types: types, from: controller())
    }
    public func definition() -> ModuleDefinition {
        Name("InkDrive")
        AsyncFunction("getRoot") { (promise: Promise) in
            Task { @MainActor in promise.resolve(self.library().root.map { ["name": $0.name] }) }
        }.runOnQueue(.main)
        AsyncFunction("pickFolder") { (promise: Promise) in
            Task { @MainActor in
                do {
                    guard !RecordingService.shared.active else { throw InkError.busy }
                    if self.library().root != nil, try self.library().pendingRecording() != nil { throw InkError.busy }
                    guard let url = try await self.choose([.folder]) else { promise.resolve(nil); return }
                    try self.library().choose(url); promise.resolve(["name": url.lastPathComponent])
                } catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("list") { (path: String, promise: Promise) in
            Task { @MainActor in do { promise.resolve(try self.library().list(path)) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("readText") { (path: String, promise: Promise) in
            Task { @MainActor in do { promise.resolve(try self.library().readText(path)) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("createFolder") { (parent: String, name: String, promise: Promise) in
            Task { @MainActor in do { try self.library().createFolder(parent: parent, name: name); promise.resolve(nil) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("createNote") { (parent: String, name: String, template: String, promise: Promise) in
            Task { @MainActor in do { promise.resolve(try self.library().createNote(parent: parent, name: name, template: template)) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("openEditor") { (path: String, promise: Promise) in
            Task { @MainActor in
                do {
                    guard self.editor == nil, self.picker == nil else { throw InkError.busy }
                    let presenter = try self.controller()
                    let session = try await self.library().open(path)
                    let editor = EditorViewController(session: session); self.editor = editor
                    let rootScope = try self.library().access()
                    let tabsKey = "inkdrive.document-tabs." + CoordinatedStore.digest(Data(rootScope.url.absoluteString.utf8))
                    let previous = UserDefaults.standard.stringArray(forKey: tabsKey) ?? []
                    editor.documentPath = path
                    editor.documentPaths = Array(([path] + previous.filter { $0 != path }).prefix(8))
                    UserDefaults.standard.set(editor.documentPaths, forKey: tabsKey)
                    editor.documentsChanged = { UserDefaults.standard.set($0, forKey: tabsKey) }
                    editor.listDocuments = { try self.library().pdfPaths() }
                    editor.openDocument = { [weak editor] next in
                        if let previous = editor?.documentPath { try self.library().refreshLessonSources(pdf: previous) }
                        return try await self.library().open(next)
                    }
                    editor.canRecord = true
                    editor.recordingAction = { [weak editor] in
                        guard let editor else { throw InkError.unavailable }
                        try await self.quickRecording(editor.documentPath)
                    }
                    editor.recordingsAction = { [weak editor] in
                        guard let editor else { return }
                        do { try self.presentRecordings(editor.documentPath, from: editor) } catch { editor.showError(error) }
                    }
                    editor.didClose = { [weak editor] in
                        self.editor = nil
                        do { try self.library().refreshLessonSources(pdf: editor?.documentPath ?? path); promise.resolve(nil) }
                        catch { promise.reject(error) }
                    }
                    presenter.present(editor, animated: true)
                } catch { self.editor = nil; promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("openRecordings") { (path: String, promise: Promise) in
            Task { @MainActor in
                do {
                    guard self.editor == nil, self.picker == nil else { throw InkError.busy }
                    try self.presentRecordings(path, from: self.controller()); promise.resolve(nil)
                } catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("pickPDF") { (promise: Promise) in
            Task { @MainActor in
                do {
                    guard let url = try await self.choose([.pdf]) else { promise.resolve(nil); return }
                    let session = try await EditorSession.open(url)
                    let editor = EditorViewController(session: session); self.editor = editor
                    editor.didClose = { self.editor = nil; promise.resolve(nil) }
                    try self.controller().present(editor, animated: true)
                } catch { self.editor = nil; promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("lessons") { (date: String, promise: Promise) in
            Task { @MainActor in
                do { promise.resolve(try self.library().lessons(date: date).map { try self.json($0) }) }
                catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("saveLesson") { (json: String, promise: Promise) in
            Task { @MainActor in
                do {
                    let lesson = try JSONDecoder().decode(LessonRecord.self, from: Data(json.utf8))
                    try self.library().saveLesson(lesson); promise.resolve(nil)
                } catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("importRecording") { (json: String, promise: Promise) in
            Task { @MainActor in
                do {
                    var lesson = try JSONDecoder().decode(LessonRecord.self, from: Data(json.utf8))
                    guard let url = try await self.choose([.audio, .mpeg4Movie]) else { promise.resolve(nil); return }
                    try self.library().importRecording(url, lesson: &lesson); promise.resolve(nil)
                } catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("startRecording") { (json: String, promise: Promise) in
            Task { @MainActor in
                do {
                    let lesson = try JSONDecoder().decode(LessonRecord.self, from: Data(json.utf8))
                    try await RecordingService.shared.start(lesson: lesson, repository: self.library()); promise.resolve(nil)
                } catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("quickStartRecording") { (path: String, promise: Promise) in
            Task { @MainActor in do { try await self.quickRecording(path); promise.resolve(nil) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("stopRecording") { (promise: Promise) in
            Task { @MainActor in do { try await RecordingService.shared.stop(); promise.resolve(nil) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("recoverRecording") { (promise: Promise) in
            Task { @MainActor in do { try RecordingService.shared.recover(repository: self.library()); promise.resolve(nil) } catch { promise.reject(error) } }
        }.runOnQueue(.main)
        AsyncFunction("archivePendingRecording") { (promise: Promise) in
            Task { @MainActor in
                do { guard !RecordingService.shared.active else { throw InkError.busy }; try self.library().archivePendingRecording(); promise.resolve(nil) }
                catch { promise.reject(error) }
            }
        }.runOnQueue(.main)
        AsyncFunction("recordingStatus") { (promise: Promise) in
            Task { @MainActor in
                let service = RecordingService.shared
                let pending = self.library().root == nil ? false : (try? self.library().pendingRecording()) != nil
                promise.resolve(["active": service.active, "seconds": service.seconds, "pending": pending,
                                 "error": service.lastError.map { $0 as Any } ?? NSNull()])
            }
        }.runOnQueue(.main)
    }
    @MainActor private func presentRecordings(_ path: String, from presenter: UIViewController) throws {
        guard presenter.presentedViewController == nil else { throw InkError.busy }
        let source = try library().recordings(for: path)
        let browser = RecordingBrowserController(rows: source.rows, scope: source.scope)
        let navigation = UINavigationController(rootViewController: browser)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        presenter.present(navigation, animated: true)
    }
    private func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    @MainActor private func quickRecording(_ path: String) async throws {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        let lesson = try library().quickLesson(pdf: path, date: formatter.string(from: Date()))
        try await RecordingService.shared.start(lesson: lesson, repository: library())
    }
}
