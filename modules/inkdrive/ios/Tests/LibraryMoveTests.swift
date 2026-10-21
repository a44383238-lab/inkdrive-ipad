import XCTest
@testable import InkDriveCore

@MainActor final class LibraryMoveTests: XCTestCase {
    func testMovingFolderKeepsPDFIdentityAndLessonReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "InkDrive-move-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repo = LibraryRepository(defaults: defaults); try repo.choose(root)
        try repo.createFolder(parent: "", name: "A"); try repo.createFolder(parent: "", name: "B")
        let path = try repo.createNote(parent: "A", name: "note", template: "ruled")
        let original = try Data(contentsOf: root.appendingPathComponent(path))
        let lesson = try repo.quickLesson(pdf: path, date: "2026-10-21"); try repo.saveLesson(lesson)
        let map = try repo.moveItems(["A", path], into: "B")
        XCTAssertEqual(map, ["A": "B/A"])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("B/A/note.pdf")), original)
        XCTAssertEqual(try repo.lessons(date: "2026-10-21").first?.pdf, "B/A/note.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A").path))
    }
    func testMovesUpdateAdaptersOutsideSourceFolderAndUnreadableCatalogAborts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "InkDrive-move-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repo = LibraryRepository(defaults: defaults); try repo.choose(root)
        try repo.createFolder(parent: "", name: "A"); try repo.createFolder(parent: "", name: "B")
        try Data("source".utf8).write(to: root.appendingPathComponent("A/source.html"))
        let cache = root.appendingPathComponent(".inkdrive/previews", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let adapter = DocumentAdapter(kind: "html-snapshot", originalPath: "A/source.html", originalSHA256: "hash", width: 500, height: 700)
        let file = cache.appendingPathComponent("notebook.pdf.adapter.json")
        try JSONEncoder().encode(adapter).write(to: file)
        _ = try repo.moveItems(["A"], into: "B")
        XCTAssertEqual(try JSONDecoder().decode(DocumentAdapter.self, from: Data(contentsOf: file)).originalPath, "B/A/source.html")
        try Data("not a directory".utf8).write(to: root.appendingPathComponent(".inkdrive/lessons"))
        XCTAssertThrowsError(try repo.moveItems(["B/A"], into: ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("B/A/source.html").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A").path))
    }
    func testMovingIndividualSourceAndNotebookUpdatesRelocatedSidecarOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "InkDrive-move-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repo = LibraryRepository(defaults: defaults); try repo.choose(root)
        try repo.createFolder(parent: "", name: "Target")
        _ = try repo.createNote(parent: "", name: "note", template: "plain")
        try Data("source".utf8).write(to: root.appendingPathComponent("source.html"))
        let adapter = DocumentAdapter(kind: "html-snapshot", originalPath: "source.html", originalSHA256: "hash", width: 500, height: 700)
        try JSONEncoder().encode(adapter).write(to: root.appendingPathComponent("note.pdf.adapter.json"))
        _ = try repo.moveItems(["source.html", "note.pdf"], into: "Target")
        let output = root.appendingPathComponent("Target/note.pdf.adapter.json")
        XCTAssertEqual(try JSONDecoder().decode(DocumentAdapter.self, from: Data(contentsOf: output)).originalPath, "Target/source.html")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("note.pdf.adapter.json").path))
    }
    func testDestinationCollisionAndDescendantMoveLeaveSourcesUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "InkDrive-move-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let repo = LibraryRepository(defaults: defaults); try repo.choose(root)
        try repo.createFolder(parent: "", name: "A"); try repo.createFolder(parent: "", name: "B")
        try repo.createFolder(parent: "A", name: "inside"); try repo.createFolder(parent: "B", name: "A")
        XCTAssertThrowsError(try repo.moveItems(["A"], into: "B"))
        XCTAssertThrowsError(try repo.moveItems(["A"], into: "A/inside"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("A/inside").path))
    }
}
