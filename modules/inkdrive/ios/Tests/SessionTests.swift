import XCTest
import UIKit
import PDFKit
import PencilKit
@testable import InkDriveCore

@MainActor private final class ControlledStorage: PDFStorage {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("controlled.pdf")
    var data: Data
    var digest = "initial"
    var pauseNextRead = false
    var pauseNextWrite = false
    var pendingRead: CheckedContinuation<FileSnapshot, Error>?
    var pendingWrite: CheckedContinuation<Void, Never>?
    var writes = 0
    init(_ data: Data) { self.data = data }
    func read() async throws -> FileSnapshot {
        if pauseNextRead { pauseNextRead = false; return try await withCheckedThrowingContinuation { pendingRead = $0 } }
        return FileSnapshot(data: data, digest: digest)
    }
    func write(_ input: Data, expected: String) async throws -> String {
        if pauseNextWrite { pauseNextWrite = false; await withCheckedContinuation { pendingWrite = $0 } }
        guard expected == digest else { throw InkError.conflict }
        writes += 1; data = input; digest = CoordinatedStore.digest(input); return digest
    }
}

@MainActor final class SessionTests: XCTestCase {
    func testInkInputDefersAutomaticPDFSaveUntilPencilLift() async throws {
        let (session, disk) = try make(), pageID = session.model.pages[0].id
        session.beginInkInput(pageID)
        try session.insertPage(at: 1, template: .ruled)
        try await Task.sleep(nanoseconds: 1_700_000_000)
        XCTAssertEqual(disk.writes, 0)
        session.endInkInput(pageID)
        try await session.flush()
        XCTAssertEqual(disk.writes, 1)
        XCTAssertFalse(session.dirty)
    }
    func testBackgroundSnapshotUsesFrozenPagesWhileEditingContinues() async throws {
        let (session, _) = try make()
        let snapshot = try session.model.snapshotJob()
        try session.insertPage(at: 1, template: .grid)
        let bytes = try await Task.detached { try snapshot.render() }.value
        XCTAssertEqual(try PDFModel(data: bytes).pages.count, 1)
        XCTAssertEqual(session.model.pages.count, 2)
    }
    private func make() throws -> (EditorSession, ControlledStorage) {
        let bytes = PDFModel.blank(template: .plain), storage = ControlledStorage(PDFModel.blank(template: .plain))
        return (try EditorSession(model: PDFModel(data: bytes), store: storage, digest: "initial"), storage)
    }
    func testEditDuringSaveIsWrittenBeforeFlushReturns() async throws {
        let (session, disk) = try make()
        try session.insertPage(at: 1, template: .ruled)
        disk.pauseNextWrite = true
        let flushing = Task { try await session.flush() }
        while disk.pendingWrite == nil { await Task.yield() }
        try session.insertPage(at: 2, template: .grid)
        disk.pendingWrite?.resume(); disk.pendingWrite = nil
        try await flushing.value
        XCTAssertEqual(try PDFModel(data: disk.data).pages.count, 3)
        XCTAssertEqual(disk.writes, 2)
        XCTAssertFalse(session.dirty)
    }
    func testEditsDuringSlowExternalReloadAreNeverDiscarded() async throws {
        let (session, disk) = try make()
        disk.pauseNextRead = true
        let reloading = Task { try await session.reloadDiscardingChanges() }
        while disk.pendingRead == nil { await Task.yield() }
        try session.insertPage(at: 1, template: .ruled)
        disk.pendingRead?.resume(returning: FileSnapshot(data: disk.data, digest: disk.digest)); disk.pendingRead = nil
        do { try await reloading.value; XCTFail("New edits must block reload") } catch {}
        XCTAssertEqual(session.model.pages.count, 2)
        XCTAssertTrue(session.dirty)
    }
    func testPageUndoAndRedoKeepStableIdentity() throws {
        let (session, _) = try make()
        try session.insertPage(at: 1, template: .plain)
        let second = session.model.pages[1].id
        session.history.undo(); XCTAssertEqual(session.model.pages.count, 1)
        session.history.redo(); XCTAssertEqual(session.model.pages[1].id, second)
    }
    func testRecordingAttachmentRemainsRecoverableAcrossRepositoryRestart() throws {
        let name = "inkdrive.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LibraryRepository(defaults: defaults); try repository.choose(directory)
        let lesson = LessonRecord(id: UUID().uuidString, date: "2026-10-20", subject: "통계", title: "수업", pdf: "notes.pdf", recordings: [], materials: [], endedAt: nil)
        try repository.savePendingRecording(PendingRecording(lesson: lesson, relative: "Recordings/preserved.m4a", finished: true))
        let reopened = LibraryRepository(defaults: defaults)
        XCTAssertEqual(try reopened.pendingRecording()?.relative, "Recordings/preserved.m4a")
        try reopened.archivePendingRecording()
        XCTAssertNil(try reopened.pendingRecording())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(".inkdrive/recovery").path).count, 1)
    }
    func testOneTapRecordingCreatesAndReusesTodaysPDFLesson() throws {
        let name = "inkdrive.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LibraryRepository(defaults: defaults); try repository.choose(folder)
        let pdf = try repository.createNote(parent: "", name: "오늘 수업", template: "plain")
        let first = try repository.quickLesson(pdf: pdf, date: "2026-10-20")
        let second = try repository.quickLesson(pdf: pdf, date: "2026-10-20")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.pdf, pdf)
        XCTAssertEqual(try repository.lessons(date: "2026-10-20").count, 1)
    }
    func testLocalAudioDraftPublishesExactlyOnceAndRetainsRecoverableDeviceCopy() throws {
        let name = "inkdrive.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = LibraryRepository(defaults: defaults); try repository.choose(folder)
        let pdf = try repository.createNote(parent: "", name: "recording", template: "plain")
        let lesson = try repository.quickLesson(pdf: pdf, date: "2026-10-20")
        let filename = UUID().uuidString + ".m4a", relative = "Recordings/" + filename
        let local = try RecordingDrafts.url(filename)
        defer { try? FileManager.default.removeItem(at: local) }
        let bytes = Data("recording transport fixture".utf8); try bytes.write(to: local)
        let pending = PendingRecording(lesson: lesson, relative: relative, finished: true, localFileName: filename)
        try repository.savePendingRecording(pending)
        let restarted = LibraryRepository(defaults: defaults)
        XCTAssertEqual(try restarted.pendingRecording()?.localFileName, filename)
        let cloud = try restarted.publishRecordingDraft(pending)
        XCTAssertEqual(try Data(contentsOf: cloud), bytes)
        _ = try restarted.publishRecordingDraft(pending)
        XCTAssertEqual(try Data(contentsOf: local), bytes)
        try Data("unrelated newer version".utf8).write(to: cloud)
        XCTAssertThrowsError(try restarted.publishRecordingDraft(pending))
        XCTAssertEqual(try Data(contentsOf: cloud), Data("unrelated newer version".utf8))
    }
}
