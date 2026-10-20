import Foundation
struct PendingRecording: Codable {
    let lesson: LessonRecord
    let relative: String
    var finished: Bool
    var localFileName: String? = nil
}
enum RecordingDrafts {
    static func url(_ filename: String) throws -> URL {
        let checked = try FileNames.checked(filename)
        guard checked.hasSuffix(".m4a") else { throw InkError.invalidName }
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("InkDrive/RecordingDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(checked)
    }
}
extension LibraryRepository {
    func pendingRecording() throws -> PendingRecording? {
        if let local = defaults.data(forKey: "inkdrive.recording.local-pending") { return try JSONDecoder().decode(PendingRecording.self, from: local) }
        let scope = try access()
        let url = scope.url.appendingPathComponent(".inkdrive/recording-pending.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(PendingRecording.self, from: Data(contentsOf: url))
    }
    func savePendingRecording(_ pending: PendingRecording) throws {
        let bytes = try JSONEncoder().encode(pending)
        defaults.set(bytes, forKey: "inkdrive.recording.local-pending")
        let scope = try access()
        let url = scope.url.appendingPathComponent(".inkdrive/recording-pending.json")
        // The device copy is authoritative while recording. An unavailable provider must not block the microphone.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? bytes.write(to: url, options: .atomic)
    }
    func clearPendingRecording() throws {
        let scope = try access()
        let url = scope.url.appendingPathComponent(".inkdrive/recording-pending.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        defaults.removeObject(forKey: "inkdrive.recording.local-pending")
    }
    func archivePendingRecording() throws {
        guard let pending = try pendingRecording() else { return }
        let scope = try access()
        let directory = scope.url.appendingPathComponent(".inkdrive/recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic)
        try clearPendingRecording()
    }
    func publishRecordingDraft(_ pending: PendingRecording) throws -> URL {
        let scope = try access()
        let destination = try FileNames.child(pending.relative, in: scope.url)
        guard let name = pending.localFileName else { return destination }
        let source = try RecordingDrafts.url(name)
        let expected = try FileHasher.digest(source)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?, result: Result<Void, Error> = .failure(InkError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: destination, options: [], error: &error) { output in
            result = Result {
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: output.path) {
                    guard try FileHasher.digest(output) == expected else { throw InkError.conflict }
                } else { try FileManager.default.copyItem(at: source, to: output) }
                guard try FileHasher.digest(output) == expected else { throw InkError.serialization }
            }
        }
        if let error { throw error }; try result.get(); return destination
    }
}
