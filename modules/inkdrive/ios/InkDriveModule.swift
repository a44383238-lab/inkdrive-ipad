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
                    editor.didClose = {
                        self.editor = nil
                        do { try self.library().refreshLessonSources(pdf: path); promise.resolve(nil) }
                        catch { promise.reject(error) }
                    }
                    presenter.present(editor, animated: true)
                } catch { self.editor = nil; promise.reject(error) }
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
    private func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
}
