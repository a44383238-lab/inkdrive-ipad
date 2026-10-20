import XCTest
import AVFoundation
@testable import InkDriveCore

@MainActor final class RecordingBrowserTests: XCTestCase {
    func testCatalogFiltersByPDFAndDeduplicatesWithoutDeletingFiles() {
        func lesson(_ pdf: String, _ day: String, _ files: [String]) -> LessonRecord {
            LessonRecord(id: UUID().uuidString, date: day, subject: "통계", title: "강의", pdf: pdf, recordings: files, materials: [], endedAt: nil)
        }
        let rows = RecordingCatalog.rows(for: "통계.pdf", lessons: [
            lesson("통계.pdf", "2026-10-19", ["Recordings/a.m4a"]),
            lesson("기타.pdf", "2026-10-20", ["Recordings/other.m4a"]),
            lesson("통계.pdf", "2026-10-20", ["Recordings/b.m4a", "Recordings/a.m4a"])
        ])
        XCTAssertEqual(rows.map(\.path), ["Recordings/b.m4a", "Recordings/a.m4a"])
    }
    func testPlayerDoesNotStartSoundOnOpeningAndEmptyListIsUsable() {
        let controller = RecordingBrowserController(rows: [], scope: nil)
        controller.loadViewIfNeeded()
        XCTAssertNil(controller.player)
        XCTAssertEqual(controller.tableView(controller.tableView, numberOfRowsInSection: 0), 0)
        XCTAssertFalse(controller.playButton.isEnabled)
    }
    func testTimestampAndClampedSeekAreStable() {
        XCTAssertEqual(RecordingBrowserController.timestamp(4311), "71:51")
        XCTAssertEqual(RecordingBrowserController.timestamp(.nan), "00:00")
        XCTAssertEqual(RecordingBrowserController.seekTarget(-10, duration: 60), 0)
        XCTAssertEqual(RecordingBrowserController.seekTarget(70, duration: 60), 60)
    }
}
