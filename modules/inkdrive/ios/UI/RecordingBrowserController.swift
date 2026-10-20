import UIKit
import AVFoundation

struct RecordingRow {
    let path: String
    let date: String
    let title: String
}

enum RecordingCatalog {
    static func rows(for pdf: String, lessons: [LessonRecord]) -> [RecordingRow] {
        var seen = Set<String>()
        return lessons.filter { $0.pdf == pdf }.sorted { ($0.date, $0.id) > ($1.date, $1.id) }.flatMap { lesson -> [RecordingRow] in
            lesson.recordings.enumerated().compactMap { index, path in
                guard seen.insert(path).inserted else { return nil }
                return RecordingRow(path: path, date: lesson.date, title: "\(lesson.date) · \(index + 1)")
            }
        }
    }
}

/// Never autoplays. Only an explicit press of Play activates the audio session.
@MainActor final class RecordingBrowserController: UITableViewController {
    let rows: [RecordingRow]
    private let scope: SecurityScope?
    private(set) var player: AVPlayer?
    let playButton = InkIcons.button("play", label: "재생")
    private let seek = UISlider()
    private let time = UILabel()
    private let name = UILabel()
    private let speed = UIButton(type: .system)
    private let loading = UIActivityIndicatorView(style: .medium)
    private var rate: Float = 1
    private var duration: Double = 0
    private var token: Any?
    private var endToken: NSObjectProtocol?
    private var interruptToken: NSObjectProtocol?
    private var selection: Int?
    private var generation = 0
    private var activated = false
    private var copies: [URL] = []
    private var durations: [String: Double] = [:]
    private let copyQueue = DispatchQueue(label: "inkdrive.audio-preview", qos: .userInitiated)

    init(rows: [RecordingRow], scope: SecurityScope?) {
        self.rows = rows; self.scope = scope
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "녹음"
        view.backgroundColor = UIColor(hex: "#F8F9FC")
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: InkIcons.image("arrow-left"), style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "필기로"
        tableView.rowHeight = 64
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 20)])
        name.text = rows.isEmpty ? "저장된 녹음 없음" : "녹음을 선택해 주세요"
        name.font = .systemFont(ofSize: 16, weight: .semibold); name.textColor = UIColor(hex: "#344A65"); name.numberOfLines = 1
        stack.addArrangedSubview(name)
        seek.minimumValue = 0; seek.maximumValue = 1; seek.isEnabled = false; seek.accessibilityLabel = "재생 위치"
        seek.addTarget(self, action: #selector(scrub), for: .valueChanged); stack.addArrangedSubview(seek)
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); time.textColor = .secondaryLabel
        time.text = "00:00 / 00:00"; stack.addArrangedSubview(time)
        let controls = UIStackView(); controls.alignment = .center; controls.spacing = 12
        let back = InkIcons.button("skip-back", label: "10초 뒤로"); back.addTarget(self, action: #selector(backward), for: .touchUpInside)
        let nextButton = InkIcons.button("skip-forward", label: "10초 앞으로"); nextButton.addTarget(self, action: #selector(forward), for: .touchUpInside)
        playButton.isEnabled = false; playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        speed.setTitle("1×", for: .normal); speed.accessibilityLabel = "재생 속도"; speed.showsMenuAsPrimaryAction = true
        speed.heightAnchor.constraint(equalToConstant: 44).isActive = true; speed.widthAnchor.constraint(equalToConstant: 58).isActive = true
        speed.menu = UIMenu(children: [0.5, 0.75, 1, 1.25, 1.5, 2].map { value in UIAction(title: "\(value)×") { [weak self] _ in
            guard let self else { return }; self.rate = Float(value); self.speed.setTitle("\(value)×", for: .normal)
            if self.player?.rate != 0 { self.player?.rate = self.rate }
        } })
        [back, playButton, nextButton, UIView(), loading, speed].forEach(controls.addArrangedSubview)
        stack.addArrangedSubview(controls); tableView.tableHeaderView = header
        interruptToken = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); generation += 1; teardown()
    }
    deinit { if let interruptToken { NotificationCenter.default.removeObserver(interruptToken) } }
    @objc private func close() { dismiss(animated: true) }
    private func pause() { player?.pause(); playButton.setImage(InkIcons.image("play"), for: .normal); playButton.accessibilityLabel = "재생" }
    private func teardown() {
        pause()
        if let token { player?.removeTimeObserver(token) }; token = nil
        if let endToken { NotificationCenter.default.removeObserver(endToken) }; endToken = nil
        player = nil
        if activated, !RecordingService.shared.active { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        activated = false
        copies.forEach { try? FileManager.default.removeItem(at: $0) }; copies = []
    }
    @objc private func togglePlay() {
        guard let player, !RecordingService.shared.active else { return }
        if player.rate != 0 { pause(); return }
        do {
            let audio = AVAudioSession.sharedInstance(); try audio.setCategory(.playback, mode: .spokenAudio); try audio.setActive(true); activated = true
            if player.currentTime().seconds >= duration - 0.1 { player.seek(to: .zero) }
            player.playImmediately(atRate: rate)
            playButton.setImage(InkIcons.image("pause"), for: .normal); playButton.accessibilityLabel = "일시정지"
        } catch { show(error) }
    }
    static func timestamp(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    static func seekTarget(_ seconds: Double, duration: Double) -> Double { max(0, min(seconds.isFinite ? seconds : 0, duration.isFinite ? duration : 0)) }
    private func jump(_ value: Double) { player?.seek(to: CMTime(seconds: Self.seekTarget(value, duration: duration), preferredTimescale: 600)) }
    @objc private func scrub() { jump(Double(seek.value)) }
    @objc private func backward() { jump((player?.currentTime().seconds ?? 0) - 10) }
    @objc private func forward() { jump((player?.currentTime().seconds ?? 0) + 10) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row], cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = durations[row.path].map(Self.timestamp) ?? "—:—"
        cell.imageView?.image = InkIcons.image("play"); cell.tintColor = UIColor(hex: "#3665BF")
        cell.accessoryType = selection == indexPath.row ? .checkmark : .none
        cell.accessibilityLabel = "\(row.title), 녹음 재생"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !RecordingService.shared.active, let scope else { return }
        generation += 1; let request = generation; let row = rows[indexPath.row]
        teardown(); playButton.isEnabled = false; seek.isEnabled = false; selection = nil
        name.text = "불러오는 중…"; time.text = "00:00 / 00:00"; loading.startAnimating(); tableView.reloadData()
        Task {
            var local: URL?
            do {
                let input = try FileNames.child(row.path, in: scope.url)
                let destination = FileManager.default.temporaryDirectory.appendingPathComponent("InkDrive-listen-\(UUID().uuidString).\(input.pathExtension)")
                local = destination
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    copyQueue.async {
                        var error: NSError?; var result: Result<Void, Error> = .failure(InkError.unavailable)
                        NSFileCoordinator().coordinate(readingItemAt: input, options: [], error: &error) { source in
                            result = Result { try FileManager.default.copyItem(at: source, to: destination) }
                        }
                        if let error { continuation.resume(throwing: error) } else { continuation.resume(with: result) }
                    }
                }
                let asset = AVURLAsset(url: destination); let loaded = try await asset.load(.duration).seconds
                guard request == generation else { try? FileManager.default.removeItem(at: destination); return }
                guard loaded.isFinite, loaded > 0 else { throw InkError.unavailable }
                duration = loaded; durations[row.path] = loaded; copies.append(destination)
                let player = AVPlayer(playerItem: AVPlayerItem(asset: asset)); self.player = player
                token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] value in
                    Task { @MainActor in
                        guard let self else { return }
                        if !self.seek.isTracking { self.seek.value = Float(value.seconds.isFinite ? value.seconds : 0) }
                        self.time.text = "\(Self.timestamp(value.seconds)) / \(Self.timestamp(self.duration))"
                    }
                }
                endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.pause() }
                }
                selection = indexPath.row; name.text = row.title; seek.maximumValue = Float(loaded); seek.value = 0; seek.isEnabled = true; playButton.isEnabled = true
                time.text = "00:00 / \(Self.timestamp(loaded))"; tableView.reloadData()
                togglePlay() // Selecting a recording is an explicit playback action; opening the list remains silent.
            } catch {
                if let local { try? FileManager.default.removeItem(at: local) }
                if request == generation { name.text = "다시 선택해 주세요"; show(error) }
            }
            if request == generation { loading.stopAnimating() }
        }
    }
    private func show(_ error: Error) {
        let alert = UIAlertController(title: "녹음", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .cancel)); present(alert, animated: true)
    }
}
