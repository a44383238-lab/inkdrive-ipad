import Foundation
import PDFKit

struct LibraryRoot: Codable { let name: String; let bookmark: Data }
struct LessonRecord: Codable {
    var schemaVersion = 1
    let id: String
    var date: String
    var subject: String
    var title: String
    var pdf: String
    var recordings: [String]
    var materials: [String]
    var endedAt: String?
    var sourceDigests: [String: String]?
    var requestedOutputs = ["transcript", "lecture-notes", "review-questions"]
}

@MainActor final class LibraryRepository {
    private let key = "inkdrive.library.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var root: LibraryRoot? {
        guard let bytes = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LibraryRoot.self, from: bytes)
    }
    func choose(_ url: URL) throws {
        let scope = SecurityScope(url)
        let data = try scope.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let root = LibraryRoot(name: url.lastPathComponent, bookmark: data)
        defaults.set(try JSONEncoder().encode(root), forKey: key)
    }
    func access() throws -> SecurityScope {
        guard let root else { throw InkError.unavailable }
        var stale = false
        let url = try URL(resolvingBookmarkData: root.bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        let scope = SecurityScope(url)
        if stale { try choose(url) }
        return scope
    }
    func list(_ relative: String) throws -> [[String: Any]] {
        let scope = try access()
        let url = try FileNames.child(relative, in: scope.url)
        return try coordinated(url, writing: false) { coordinated in
            try FileManager.default.contentsOfDirectory(at: coordinated, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: .skipsHiddenFiles).compactMap { item in
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let directory = values.isDirectory == true
                guard directory || ["pdf", "md", "txt"].contains(item.pathExtension.lowercased()) else { return nil }
                return ["name": item.lastPathComponent, "path": relative.isEmpty ? item.lastPathComponent : relative + "/" + item.lastPathComponent,
                        "directory": directory, "bytes": values.fileSize ?? 0, "modified": values.contentModificationDate?.timeIntervalSince1970 ?? 0]
            }
        }
    }
    func pdfPaths() throws -> [String] {
        let scope = try access()
        return try coordinated(scope.url, writing: false) { root in
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
            var result: [String] = [], visited = 0
            while let item = walker.nextObject() as? URL {
                visited += 1; if visited > 10000 { break }
                if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { walker.skipDescendants(); continue }
                if item.pathExtension.lowercased() == "pdf" { result.append(String(item.path.dropFirst(root.path.count + 1))) }
            }
            return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
    func createFolder(parent: String, name: String) throws {
        let scope = try access(), checked = try FileNames.checked(name)
        let directory = try FileNames.child(parent, in: scope.url)
        try coordinated(directory, writing: true) { url in
            try FileManager.default.createDirectory(at: url.appendingPathComponent(checked), withIntermediateDirectories: false)
        }
    }
    func createNote(parent: String, name: String, template: String) throws -> String {
        let scope = try access()
        var checked = try FileNames.checked(name)
        if !checked.lowercased().hasSuffix(".pdf") { checked += ".pdf" }
        let relative = parent.isEmpty ? checked : parent + "/" + checked
        let url = try FileNames.child(relative, in: scope.url)
        try coordinated(url.deletingLastPathComponent(), writing: true) { directory in
            let destination = directory.appendingPathComponent(checked)
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            try PDFModel.blank(template: PaperTemplate(rawValue: template) ?? .plain).write(to: destination, options: .withoutOverwriting)
        }
        return relative
    }
    func open(_ relative: String) async throws -> EditorSession {
        let scope = try access()
        let url = try FileNames.child(relative, in: scope.url)
        return try await EditorSession.open(url, scope: scope)
    }
    func lessons(date: String) throws -> [LessonRecord] {
        let scope = try access()
        let folder = scope.url.appendingPathComponent(".inkdrive/lessons", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try coordinated(folder, writing: false) { url in
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map {
                try JSONDecoder().decode(LessonRecord.self, from: Data(contentsOf: $0))
            }.filter { $0.date == date }
        }
    }
    func recordings(for pdf: String) throws -> (rows: [RecordingRow], scope: SecurityScope) {
        let scope = try access()
        _ = try FileNames.child(pdf, in: scope.url)
        let folder = scope.url.appendingPathComponent(".inkdrive/lessons", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return ([], scope) }
        let lessons: [LessonRecord] = try coordinated(folder, writing: false) { directory in
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { try JSONDecoder().decode(LessonRecord.self, from: Data(contentsOf: $0)) }
        }
        return (RecordingCatalog.rows(for: pdf, lessons: lessons), scope)
    }
    func saveLesson(_ lesson: LessonRecord) throws {
        guard lesson.schemaVersion == 1, UUID(uuidString: lesson.id) != nil,
              !lesson.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lesson.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              lesson.date.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { throw InkError.invalidName }
        let scope = try access()
        let pdfURL = try FileNames.child(lesson.pdf, in: scope.url)
        guard pdfURL.pathExtension.lowercased() == "pdf", FileManager.default.fileExists(atPath: pdfURL.path) else { throw InkError.invalidPDF }
        for path in lesson.recordings + lesson.materials { _ = try FileNames.child(path, in: scope.url) }
        var stored = lesson
        if stored.endedAt != nil {
            var hashes: [String: String] = [:]
            for relative in [stored.pdf] + stored.recordings + stored.materials {
                let input = try FileNames.child(relative, in: scope.url)
                hashes[relative] = try coordinated(input, writing: false) { try FileHasher.digest($0) }
            }
            stored.sourceDigests = hashes
        } else { stored.sourceDigests = nil }
        let directory = scope.url.appendingPathComponent(".inkdrive/lessons", isDirectory: true)
        try coordinated(scope.url, writing: true) { _ in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(stored).write(to: directory.appendingPathComponent(lesson.id + ".json"), options: .atomic)
        }
    }
    func quickLesson(pdf: String, date: String) throws -> LessonRecord {
        if let existing = try lessons(date: date).last(where: { $0.pdf == pdf && $0.endedAt == nil }) { return existing }
        let components = pdf.split(separator: "/").map(String.init)
        let title = URL(fileURLWithPath: components.last ?? pdf).deletingPathExtension().lastPathComponent
        let subject = components.count > 1 ? components[components.count - 2] : "수업"
        let lesson = LessonRecord(id: UUID().uuidString, date: date, subject: subject, title: title, pdf: pdf, recordings: [], materials: [], endedAt: nil)
        try saveLesson(lesson); return lesson
    }
    func refreshLessonSources(pdf relative: String) throws {
        let scope = try access()
        let folder = scope.url.appendingPathComponent(".inkdrive/lessons", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let data = try coordinated(folder, writing: false) { directory in
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.map { try Data(contentsOf: $0) }
        }
        for bytes in data {
            let lesson = try JSONDecoder().decode(LessonRecord.self, from: bytes)
            if lesson.pdf == relative, lesson.endedAt != nil { try saveLesson(lesson) }
        }
    }
    func readText(_ relative: String) throws -> String {
        let scope = try access()
        let url = try FileNames.child(relative, in: scope.url)
        guard ["md", "txt"].contains(url.pathExtension.lowercased()) else { throw InkError.invalidName }
        return try coordinated(url, writing: false) { input in
            let size = try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5_000_000 else { throw InkError.unavailable }
            return try String(contentsOf: input, encoding: .utf8)
        }
    }
    func importRecording(_ source: URL, lesson: inout LessonRecord) throws {
        let sourceScope = SecurityScope(source), rootScope = try access()
        let ext = source.pathExtension.lowercased()
        guard ["m4a", "mp3", "wav", "aac", "mp4", "caf"].contains(ext) else { throw InkError.invalidName }
        let relative = "Recordings/\(lesson.date)_\(UUID().uuidString).\(ext)"
        let destination = try FileNames.child(relative, in: rootScope.url)
        var error: NSError?, result: Result<Void, Error> = .failure(InkError.unavailable)
        NSFileCoordinator().coordinate(readingItemAt: sourceScope.url, options: [], writingItemAt: destination, options: [], error: &error) { input, output in
            result = Result {
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: input, to: output)
            }
        }
        if let error { throw error }; try result.get()
        lesson.recordings.append(relative)
        try saveLesson(lesson)
    }
    private func coordinated<T>(_ url: URL, writing: Bool, work: (URL) throws -> T) throws -> T {
        var error: NSError?, result: Result<T, Error> = .failure(InkError.unavailable)
        let coordinator = NSFileCoordinator()
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error) { coordinatedURL in
                result = Result { try work(coordinatedURL) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordinatedURL in
                result = Result { try work(coordinatedURL) }
            }
        }
        if let error { throw error }; return try result.get()
    }
}
