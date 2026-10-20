import AVFoundation
import UIKit

@MainActor final class RecordingService: NSObject, AVAudioRecorderDelegate {
    static let shared = RecordingService()
    private var recorder: AVAudioRecorder?
    private var scope: SecurityScope?
    private var lesson: LessonRecord?
    private var repository: LibraryRepository?
    private var relative = ""
    private var finishing: CheckedContinuation<Void, Error>?
    private var interruption: NSObjectProtocol?
    private(set) var lastError: String?
    var active: Bool { recorder != nil }
    var seconds: Double { recorder?.currentTime ?? 0 }
    func start(lesson: LessonRecord, repository: LibraryRepository) async throws {
        guard !active else { throw InkError.busy }
        guard try repository.pendingRecording() == nil else {
            throw NSError(domain: "InkDrive", code: 2, userInfo: [NSLocalizedDescriptionKey: "복구 대기 녹음이 있어요. 먼저 녹음 복구를 실행해 주세요."])
        }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { throw NSError(domain: "InkDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "설정에서 마이크 권한을 허용해 주세요."]) }
        let scope = try repository.access()
        let relative = "Recordings/\(lesson.date)_\(UUID().uuidString).m4a"
        let destination = try FileNames.child(relative, in: scope.url)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try audio.setActive(true)
        try repository.savePendingRecording(PendingRecording(lesson: lesson, relative: relative, finished: false))
        let recorder = try AVAudioRecorder(url: destination, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            try? audio.setActive(false); throw InkError.unavailable
        }
        self.scope = scope; self.relative = relative; self.lesson = lesson; self.repository = repository; self.recorder = recorder; lastError = nil
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.active else { return }
                do { try await self.stop() } catch { self.lastError = error.localizedDescription }
            }
        }
    }
    func stop() async throws {
        guard let recorder else { return }
        guard finishing == nil else { throw InkError.busy }
        try await withCheckedThrowingContinuation { continuation in finishing = continuation; recorder.stop() }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finished(success: flag) }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.finished(success: false) }
    }
    private func finished(success: Bool) {
        guard recorder != nil else { return }
        let completion = finishing; finishing = nil
        defer {
            recorder = nil; scope = nil; lesson = nil; repository = nil
            if let interruption { NotificationCenter.default.removeObserver(interruption) }; interruption = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        do {
            guard success, var lesson, let repository else { throw InkError.unavailable }
            try repository.savePendingRecording(PendingRecording(lesson: lesson, relative: relative, finished: true))
            // Reload before append: recording can outlive subject/title updates from the library.
            if let latest = try repository.lessons(date: lesson.date).first(where: { $0.id == lesson.id }) { lesson = latest }
            if !lesson.recordings.contains(relative) { lesson.recordings.append(relative) }
            try repository.saveLesson(lesson)
            try repository.clearPendingRecording()
            completion?.resume()
        } catch { lastError = error.localizedDescription; completion?.resume(throwing: error) }
    }
    func recover(repository: LibraryRepository) throws {
        guard !active else { throw InkError.busy }
        guard let pending = try repository.pendingRecording() else { return }
        let scope = try repository.access()
        let url = try FileNames.child(pending.relative, in: scope.url)
        let audio = try AVAudioPlayer(contentsOf: url) // Inspection only; never played.
        guard audio.duration > 0 else { throw InkError.unavailable }
        var lesson = try repository.lessons(date: pending.lesson.date).first(where: { $0.id == pending.lesson.id }) ?? pending.lesson
        if !lesson.recordings.contains(pending.relative) { lesson.recordings.append(pending.relative) }
        try repository.saveLesson(lesson); try repository.clearPendingRecording(); lastError = nil
    }
}
