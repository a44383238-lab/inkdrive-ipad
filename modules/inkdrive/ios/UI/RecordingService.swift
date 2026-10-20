import AVFoundation
import UIKit

@MainActor final class RecordingService: NSObject, AVAudioRecorderDelegate {
    static let shared = RecordingService()
    private var recorder: AVAudioRecorder?
    private var scope: SecurityScope?
    private var lesson: LessonRecord?
    private var repository: LibraryRepository?
    private var relative = ""
    private var localFileName: String?
    private var starting = false
    private var finishing: CheckedContinuation<Void, Error>?
    private var interruption: NSObjectProtocol?
    private(set) var lastError: String?
    var active: Bool { recorder != nil }
    var seconds: Double { recorder?.currentTime ?? 0 }
    func start(lesson: LessonRecord, repository: LibraryRepository) async throws {
        guard !active, !starting else { throw InkError.busy }
        starting = true
        defer { starting = false }
        if let pending = try repository.pendingRecording() {
            let root = try repository.access()
            let pendingURL = try pending.localFileName.map(RecordingDrafts.url) ?? FileNames.child(pending.relative, in: root.url)
            let size = (try? pendingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size == 0 { try repository.clearPendingRecording() }
            else { try recover(repository: repository) }
        }
        guard try repository.pendingRecording() == nil else {
            throw NSError(domain: "InkDrive", code: 2, userInfo: [NSLocalizedDescriptionKey: "복구 대기 녹음이 있어요. 먼저 녹음 복구를 실행해 주세요."])
        }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { throw NSError(domain: "InkDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "설정에서 마이크 권한을 허용해 주세요."]) }
        let scope = try repository.access()
        let filename = "\(lesson.date)_\(UUID().uuidString).m4a"
        let relative = "Recordings/" + filename
        let destination = try RecordingDrafts.url(filename)
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.record, mode: .default, options: [.allowBluetooth])
        try audio.setActive(true)
        try repository.savePendingRecording(PendingRecording(lesson: lesson, relative: relative, finished: false, localFileName: filename))
        let recorder = try AVAudioRecorder(url: destination, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else {
            try? audio.setActive(false)
            if ((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) == 0 { try? repository.clearPendingRecording() }
            throw NSError(domain: "InkDrive", code: 6, userInfo: [NSLocalizedDescriptionKey: "마이크를 시작하지 못했어요. 다른 앱의 녹음을 종료한 뒤 다시 눌러 주세요."])
        }
        self.scope = scope; self.relative = relative; self.localFileName = filename; self.lesson = lesson; self.repository = repository; self.recorder = recorder; lastError = nil
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
            recorder = nil; scope = nil; lesson = nil; repository = nil; localFileName = nil
            if let interruption { NotificationCenter.default.removeObserver(interruption) }; interruption = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        do {
            guard success, var lesson, let repository else { throw InkError.unavailable }
            let pending = PendingRecording(lesson: lesson, relative: relative, finished: true, localFileName: localFileName)
            try repository.savePendingRecording(pending)
            _ = try repository.publishRecordingDraft(pending)
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
        let url = try pending.localFileName.map(RecordingDrafts.url) ?? FileNames.child(pending.relative, in: scope.url)
        let audio = try AVAudioPlayer(contentsOf: url) // Inspection only; never played.
        guard audio.duration > 0 else { throw InkError.unavailable }
        _ = try repository.publishRecordingDraft(pending)
        var lesson = try repository.lessons(date: pending.lesson.date).first(where: { $0.id == pending.lesson.id }) ?? pending.lesson
        if !lesson.recordings.contains(pending.relative) { lesson.recordings.append(pending.relative) }
        try repository.saveLesson(lesson); try repository.clearPendingRecording(); lastError = nil
    }
}
