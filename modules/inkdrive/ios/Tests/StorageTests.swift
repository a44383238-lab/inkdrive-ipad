import XCTest
@testable import InkDriveCore

final class StorageTests: XCTestCase {
    func testStreamingHashMatchesKnownSHA256() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try FileHasher.digest(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testExternalModificationRefusesOverwrite() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("original.pdf")
        try Data("original".utf8).write(to: url)
        let store = CoordinatedStore(url: url)
        let initial = try await store.read()
        try Data("external edit".utf8).write(to: url)
        do {
            _ = try await store.write(Data("local edit".utf8), expected: initial.digest)
            XCTFail("Must refuse stale overwrite")
        } catch { XCTAssertEqual(try Data(contentsOf: url), Data("external edit".utf8)) }
    }
    func testSameURLReceivesEditsAndNoSiblingCopyAppears() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("original.pdf")
        try Data("old".utf8).write(to: url)
        let store = CoordinatedStore(url: url)
        let initial = try await store.read()
        _ = try await store.write(Data("new".utf8), expected: initial.digest)
        XCTAssertEqual(try Data(contentsOf: url), Data("new".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["original.pdf"])
    }
    func testNamesCannotEscapeSelectedFolder() throws {
        XCTAssertEqual(try FileNames.checked(" 통계 "), "통계")
        for value in ["..", "../a", "a/b", "NUL", "x.", "a:b", "COM1.pdf"] {
            XCTAssertThrowsError(try FileNames.checked(value))
        }
    }
}
