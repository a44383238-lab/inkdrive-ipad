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
