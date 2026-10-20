import Foundation
struct PendingRecording: Codable {
    let lesson: LessonRecord
    let relative: String
    var finished: Bool
}
extension LibraryRepository {
    func pendingRecording() throws -> PendingRecording? {
        let scope = try access()
        let url = scope.url.appendingPathComponent(".inkdrive/recording-pending.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PendingRecording.self, from: Data(contentsOf: url))
    }
    func savePendingRecording(_ pending: PendingRecording) throws {
        let scope = try access()
        let url = scope.url.appendingPathComponent(".inkdrive/recording-pending.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: url, options: .atomic)
    }
    func clearPendingRecording() throws {
        let scope = try access()
        let url = scope.url.appendingPathComponent(".inkdrive/recording-pending.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func archivePendingRecording() throws {
        guard let pending = try pendingRecording() else { return }
        let scope = try access()
        let directory = scope.url.appendingPathComponent(".inkdrive/recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        try clearPendingRecording()
    }
}
