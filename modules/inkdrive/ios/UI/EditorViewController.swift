import UIKit
import PDFKit
import PencilKit
import AVFoundation

@MainActor final class EditorViewController: UIViewController, UIPencilInteractionDelegate, UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate {
    private(set) var session: EditorSession
    var documentPath = ""
    var documentPaths: [String] = []
    var openDocument: ((String) async throws -> EditorSession)?
    var documentsChanged: (([String]) -> Void)?
    var listDocuments: (() throws -> [String])?
    private let tabs = UIStackView()
    private var switchingDocument = false
    private var needsInitialPageFit = true
    private var savedPages: [String: Int] = [:]
    let pdfView = PDFView()
    let provider = OverlayProvider()
    private(set) var tool: EditorTool = .pen
    private var previousTool: EditorTool = .pen
    private var configurations: [String: ToolSettings] = [:]
    var settings: ToolSettings { configurations[tool.rawValue] ?? ToolSettings() }
    private let floating = UIView()
    private let toolbarStack = UIStackView()
    private var toolbarVertical = UserDefaults.standard.bool(forKey: "inkdrive.toolbar-vertical")
    private var toolAxisConstraint: NSLayoutConstraint?
    private let pageSlider = UISlider()
    private let pageNumber = UILabel()
    private let pagePreview = UIImageView()
    private var pageObserver: NSObjectProtocol?
    private let recordingStrip = UIStackView()
    private var recordingBrowser: RecordingBrowserController?
    private let dockSeek = UISlider()
    private let dockPlay = InkIcons.button("play", label: "녹음 재생", compact: true)
    private let dockTime = UILabel()
    private let viewport = NotebookViewport()
    private var visibleTools: [EditorTool] = EditorTool.allCases
    private let recordButton = UIButton(type: .system)
    var recordingAction: (() async throws -> Void)?
    var recordingsAction: (() -> Void)?
    var canRecord = false
    private var startingRecording = false
    private let tools = UIStackView()
    private let status = UILabel()
    private let toolScroll = UIScrollView()
    private var toolButtons: [EditorTool: UIButton] = [:]
    private var observerTokens: [NSObjectProtocol] = []
    private var closing = false
    private let recordingLabel = UILabel()
    private var recordingTimer: Timer?
    var didClose: (() -> Void)?

    init(session: EditorSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen; isModalInPresentation = true
        if let saved = UserDefaults.standard.stringArray(forKey: "inkdrive.visible-tools.v2") {
            let restored = saved.compactMap(EditorTool.init(rawValue:))
            if !restored.isEmpty { visibleTools = restored }
        }
        if let bytes = UserDefaults.standard.data(forKey: "inkdrive.tools.v1"),
           let decoded = try? JSONDecoder().decode([String: ToolSettings].self, from: bytes) { configurations = decoded }
        if UserDefaults.standard.object(forKey: "inkdrive.tool-presets.v2") == nil {
            let defaults: [(EditorTool, String, Double, Double)] = [(.pen, "#202020", 0.5, 1), (.pen, "#2455D6", 0.5, 1), (.pen, "#DB3249", 0.5, 1), (.marker, "#79E047", 15, 0.4)]
            let presets = defaults.compactMap { type, color, width, opacity -> Data? in
                var value = ToolSettings(); value.color = color; value.width = width; value.opacity = opacity
                return try? JSONEncoder().encode(ToolPreset(tool: type, settings: value))
            }
            UserDefaults.standard.set(presets, forKey: "inkdrive.tool-presets.v2")
        }
        if configurations[EditorTool.marker.rawValue] == nil {
            var marker = ToolSettings(); marker.color = "#FFE247"; marker.width = 18; marker.opacity = 0.45
            configurations[EditorTool.marker.rawValue] = marker
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = UIColor(white: 0.105, alpha: 1); overrideUserInterfaceStyle = .dark; view.tintColor = UIColor(hex: "#F4CA52")
        provider.editor = self
        pdfView.isInMarkupMode = true
        pdfView.pageOverlayViewProvider = provider
        pdfView.document = session.model.pdf
        pdfView.displayMode = (UserDefaults.standard.object(forKey: "inkdrive.continuous-pages") as? Bool ?? true) ? .singlePageContinuous : .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        pdfView.displayBox = .cropBox; pdfView.autoScales = true; pdfView.pageShadowsEnabled = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(pdfView)
        let header = UIStackView(); header.spacing = 4; header.alignment = .center
        header.addArrangedSubview(iconButton("arrow-left", label: "서재로", action: #selector(closeEditor)))
        status.text = session.store.url.deletingPathExtension().lastPathComponent; status.font = .systemFont(ofSize: 12, weight: .medium); status.numberOfLines = 1; status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.isHidden = true; header.addArrangedSubview(status); header.addArrangedSubview(UIView())
        recordButton.accessibilityLabel = "녹음 시작"
        recordButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        recordButton.layer.cornerRadius = 3; recordButton.backgroundColor = .clear
        recordButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        recordButton.widthAnchor.constraint(equalToConstant: 76).isActive = true
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        header.addArrangedSubview(recordButton)
        if recordingsAction != nil { header.addArrangedSubview(iconButton("list-music", label: "녹음 목록", action: #selector(showRecordings))) }
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRecordingButton() }
        }
        refreshRecordingButton()
        header.addArrangedSubview(iconButton("layers", label: "페이지", action: #selector(showPages)))
        header.addArrangedSubview(iconButton("sliders-horizontal", label: "보기 설정", action: #selector(displaySettings)))
        header.addArrangedSubview(iconButton("ellipsis", label: "문서 메뉴", action: #selector(more)))
        header.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(header)
        let tabScroll = UIScrollView(); tabScroll.showsHorizontalScrollIndicator = false; tabScroll.translatesAutoresizingMaskIntoConstraints = false
        tabs.axis = .horizontal; tabs.spacing = 1; tabs.translatesAutoresizingMaskIntoConstraints = false; tabScroll.addSubview(tabs); view.addSubview(tabScroll)
        let hasTabs = openDocument != nil
        NSLayoutConstraint.activate([
            tabScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2), tabScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), tabScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), tabScroll.heightAnchor.constraint(equalToConstant: hasTabs ? 28 : 0),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor), tabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor), tabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor), tabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), header.heightAnchor.constraint(equalToConstant: 36),
            pdfView.topAnchor.constraint(equalTo: tabScroll.bottomAnchor, constant: 0), pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor), pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        rebuildTabs(); buildToolbar(); buildPageScrubber(); buildRecordingDock()
        let pencil = UIPencilInteraction(); pencil.delegate = self; view.addInteraction(pencil)
        let undo = UITapGestureRecognizer(target: self, action: #selector(undoAction))
        undo.numberOfTouchesRequired = 2; undo.numberOfTapsRequired = 2; undo.delegate = self
        undo.cancelsTouchesInView = false; pdfView.addGestureRecognizer(undo)
        bindSession()
        observerTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.backgroundSave() }
        })
        observerTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do { try await self.session.checkExternalChange() } catch { self.showError(error) }
            }
        })
    }
    deinit { observerTokens.forEach(NotificationCenter.default.removeObserver); recordingTimer?.invalidate(); if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) } }
    private func bindSession() {
        session.didChange = { [weak self] in self?.refresh() }
        session.statusChanged = { [weak self] value in self?.status.accessibilityValue = value }
    }
    private func rebuildTabs() {
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard openDocument != nil else { return }
        for path in documentPaths {
            let tab = UIButton(type: .system)
            tab.setTitle(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, for: .normal)
            tab.titleLabel?.font = .systemFont(ofSize: 12, weight: path == documentPath ? .semibold : .regular)
            tab.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            tab.backgroundColor = path == documentPath ? UIColor(white: 0.07, alpha: 1) : .clear; tab.layer.cornerRadius = 0
            tab.tintColor = path == documentPath ? UIColor(hex: "#F4CA52") : UIColor(white: 0.55, alpha: 1)
            tab.accessibilityLabel = "문서 탭 " + path; tab.accessibilityValue = path == documentPath ? "선택됨" : nil
            tab.addAction(UIAction { [weak self] _ in Task { @MainActor in await self?.switchToDocument(path) } }, for: .touchUpInside)
            if path != documentPath { tab.menu = UIMenu(children: [UIAction(title: "탭 닫기", attributes: .destructive) { [weak self] _ in
                guard let self else { return }; self.documentPaths.removeAll { $0 == path }; self.rebuildTabs(); self.documentsChanged?(self.documentPaths)
            }]) }
            tabs.addArrangedSubview(tab)
        }
        if listDocuments != nil { tabs.addArrangedSubview(iconButton("plus", label: "다른 문서 열기", action: #selector(browseDocuments))) }
    }
    @objc private func browseDocuments() {
        do {
            let controller = DocumentTabsController(paths: try listDocuments?() ?? []) { [weak self] path in
                guard let self else { return }
                if !self.documentPaths.contains(path) { self.documentPaths.append(path) }
                Task { @MainActor in await self.switchToDocument(path) }
            }
            let navigation = UINavigationController(rootViewController: controller); navigation.modalPresentationStyle = .pageSheet
            present(navigation, animated: true)
        } catch { showError(error) }
    }
    func switchToDocument(_ path: String) async {
        guard path != documentPath, !switchingDocument, !startingRecording, !closing, let openDocument else { return }
        switchingDocument = true; view.isUserInteractionEnabled = false
        defer { switchingDocument = false; view.isUserInteractionEnabled = true }
        do {
            provider.commitAll(); try await session.flush()
            recordingBrowser?.shutdown(); recordingBrowser = nil; recordingStrip.isHidden = true
            if let page = pdfView.currentPage { savedPages[documentPath] = session.model.pdf.index(for: page) }
            let next = try await openDocument(path)
            // Drain outgoing overlays while they still refer to their original session.
            pdfView.document = nil; provider.overlays.removeAll()
            session.didChange = nil; session.statusChanged = nil; session = next; documentPath = path; bindSession()
            pdfView.document = next.model.pdf; needsInitialPageFit = true; view.setNeedsLayout()
            if let page = next.model.pdf.page(at: min(savedPages[path] ?? 0, next.model.pages.count - 1)) { pdfView.go(to: page) }
            status.text = next.store.url.deletingPathExtension().lastPathComponent
            rebuildTabs(); documentsChanged?(documentPaths); provider.applyTool(); updatePageNumber()
        } catch { showError(error) }
    }
    private func refreshRecordingButton() {
        let service = RecordingService.shared
        recordButton.isEnabled = !startingRecording
        recordButton.tintColor = service.active ? UIColor(hex: "#F46B75") : UIColor(hex: "#E8C65A")
        recordButton.setImage(InkIcons.image(service.active ? "square" : "mic"), for: .normal)
        let elapsed = Int(service.seconds)
        recordButton.setTitle(service.active ? String(format: "  %02d:%02d", elapsed / 60, elapsed % 60) : "", for: .normal)
        recordButton.accessibilityLabel = service.active ? "녹음 종료" : "녹음 시작"
        recordButton.accessibilityValue = service.active ? "녹음 중" : nil
    }
    @objc private func showRecordings() { recordingsAction?() }
    @objc func toggleRecording() {
        guard !startingRecording, !switchingDocument, !closing else { return }
        startingRecording = true; refreshRecordingButton()
        Task {
            defer { startingRecording = false; refreshRecordingButton() }
            do {
                if RecordingService.shared.active { try await RecordingService.shared.stop() }
                else {
                    guard canRecord, let recordingAction else {
                        throw NSError(domain: "InkDrive", code: 5, userInfo: [NSLocalizedDescriptionKey: "서재의 PDF를 열면 바로 녹음할 수 있어요."])
                    }
                    recordingBrowser?.shutdown(); recordingBrowser = nil; recordingStrip.isHidden = true
                    try await recordingAction()
                }
            } catch {
                let alert = UIAlertController(title: "녹음", message: error.localizedDescription, preferredStyle: .alert)
                if AVAudioSession.sharedInstance().recordPermission == .denied {
                    alert.addAction(UIAlertAction(title: "설정", style: .default) { _ in
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    })
                }
                alert.addAction(UIAlertAction(title: "확인", style: .cancel))
                present(alert, animated: true)
            }
        }
    }
    private func buildRecordingDock() {
        recordingStrip.axis = .horizontal; recordingStrip.spacing = 5; recordingStrip.alignment = .center
        recordingStrip.backgroundColor = UIColor(white: 0.2, alpha: 0.9); recordingStrip.layer.cornerRadius = 4
        recordingStrip.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(recordingStrip)
        let back = iconButton("skip-back", label: "녹음 10초 뒤로", action: #selector(dockBack))
        dockPlay.addTarget(self, action: #selector(dockToggle), for: .touchUpInside)
        let next = iconButton("skip-forward", label: "녹음 10초 앞으로", action: #selector(dockForward))
        dockTime.text = "00:00"; dockTime.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        dockSeek.accessibilityLabel = "녹음 빠른 재생 위치"; dockSeek.minimumValue = 0; dockSeek.maximumValue = 1; dockSeek.isEnabled = false
        dockSeek.addTarget(self, action: #selector(dockScrub), for: .valueChanged)
        [back, dockPlay, next, dockTime, dockSeek, iconButton("list-music", label: "녹음 설정과 목록", action: #selector(showRecordings))].forEach(recordingStrip.addArrangedSubview)
        NSLayoutConstraint.activate([recordingStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), recordingStrip.topAnchor.constraint(equalTo: pdfView.topAnchor, constant: 8), recordingStrip.widthAnchor.constraint(equalToConstant: 370), recordingStrip.heightAnchor.constraint(equalToConstant: 36)])
        dockPlay.isEnabled = false; recordingStrip.isHidden = true
    }
    func presentRecordingBrowser(_ candidate: RecordingBrowserController) {
        let browser: RecordingBrowserController
        if let existing = recordingBrowser, existing.rows.map(\.path) == candidate.rows.map(\.path) { browser = existing }
        else { recordingBrowser?.shutdown(); recordingBrowser = candidate; browser = candidate }
        browser.keepPlayingWhenHidden = true
        browser.playbackChanged = { [weak self] current, duration, playing in
            guard let self else { return }
            self.dockTime.text = RecordingBrowserController.timestamp(current)
            self.dockSeek.maximumValue = Float(max(1, duration)); self.dockSeek.isEnabled = duration > 0
            if !self.dockSeek.isTracking { self.dockSeek.value = Float(current.isFinite ? current : 0) }
            self.dockPlay.isEnabled = duration > 0
            self.dockPlay.setImage(InkIcons.image(playing ? "pause" : "play"), for: .normal)
            self.dockPlay.accessibilityLabel = playing ? "녹음 일시정지" : "녹음 재생"
        }
        recordingStrip.isHidden = false
        let navigation = UINavigationController(rootViewController: browser)
        navigation.modalPresentationStyle = .popover; navigation.overrideUserInterfaceStyle = .dark
        navigation.preferredContentSize = CGSize(width: 370, height: 420)
        navigation.popoverPresentationController?.sourceView = recordingStrip
        navigation.popoverPresentationController?.sourceRect = recordingStrip.bounds
        navigation.popoverPresentationController?.delegate = self
        present(navigation, animated: true)
    }
    @objc private func dockToggle() { recordingBrowser?.toggleFromDock() }
    @objc private func dockScrub() { recordingBrowser?.seekFromDock(Double(dockSeek.value)) }
    @objc private func dockBack() { recordingBrowser?.seekFromDock(Double(dockSeek.value) - 10) }
    @objc private func dockForward() { recordingBrowser?.seekFromDock(Double(dockSeek.value) + 10) }
    private func updateToolbarAxis() {
        toolAxisConstraint?.isActive = false
        toolbarStack.axis = toolbarVertical ? .vertical : .horizontal
        tools.axis = toolbarStack.axis
        toolAxisConstraint = toolbarVertical ? tools.widthAnchor.constraint(equalTo: toolScroll.frameLayoutGuide.widthAnchor) : tools.heightAnchor.constraint(equalTo: toolScroll.frameLayoutGuide.heightAnchor)
        toolAxisConstraint?.isActive = true
        // Cross-axis size is supplied by the toolbar's constrained stack.
        view.setNeedsLayout()
    }
    @objc private func rotateToolbar() {
        toolbarVertical.toggle(); UserDefaults.standard.set(toolbarVertical, forKey: "inkdrive.toolbar-vertical")
        updateToolbarAxis()
    }
    private func buildPageScrubber() {
        pageSlider.minimumValue = 1; pageSlider.maximumValue = Float(max(2, session.model.pages.count))
        pageSlider.tintColor = UIColor(white: 0.5, alpha: 1); pageSlider.accessibilityLabel = "빠른 페이지 이동"
        pageSlider.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(pageSlider)
        pageSlider.addTarget(self, action: #selector(scrubPage), for: .valueChanged)
        pageSlider.addTarget(self, action: #selector(endScrub), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        pageNumber.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular); pageNumber.textAlignment = .center
        pageNumber.textColor = UIColor(white: 0.8, alpha: 1); pageNumber.backgroundColor = UIColor(white: 0.22, alpha: 0.8)
        pageNumber.layer.cornerRadius = 3; pageNumber.clipsToBounds = true
        pageNumber.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(pageNumber)
        pagePreview.contentMode = .scaleAspectFit; pagePreview.backgroundColor = UIColor(white: 0.15, alpha: 1)
        pagePreview.layer.borderWidth = 6; pagePreview.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        pagePreview.isHidden = true; pagePreview.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(pagePreview)
        NSLayoutConstraint.activate([
            pageSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), pageSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), pageSlider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4), pageSlider.heightAnchor.constraint(equalToConstant: 32),
            pageNumber.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18), pageNumber.bottomAnchor.constraint(equalTo: pageSlider.topAnchor, constant: -4), pageNumber.widthAnchor.constraint(equalToConstant: 78), pageNumber.heightAnchor.constraint(equalToConstant: 23),
            pagePreview.centerXAnchor.constraint(equalTo: pageSlider.centerXAnchor), pagePreview.bottomAnchor.constraint(equalTo: pageSlider.topAnchor, constant: -12), pagePreview.widthAnchor.constraint(equalToConstant: 100), pagePreview.heightAnchor.constraint(equalToConstant: 126)
        ])
        pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in Task { @MainActor in self?.updatePageNumber() } }
        updatePageNumber()
    }
    private func updatePageNumber() {
        let count = session.model.pages.count
        let index = pdfView.currentPage.map { session.model.pdf.index(for: $0) + 1 } ?? 1
        pageSlider.maximumValue = Float(max(2, count)); pageSlider.isEnabled = count > 1
        if !pageSlider.isTracking { pageSlider.value = Float(index) }
        pageNumber.text = "\(index)/\(count) 페이지"
    }
    @objc private func scrubPage() {
        let index = max(0, min(session.model.pages.count - 1, Int(pageSlider.value.rounded()) - 1))
        guard let page = session.model.pdf.page(at: index) else { return }
        provider.commitAll(); pdfView.go(to: page)
        pagePreview.image = NotebookPreview.image(session.model.pages[index], size: CGSize(width: 160, height: 200)); pagePreview.isHidden = false
        updatePageNumber()
    }
    @objc private func endScrub() { pagePreview.isHidden = true }
    @objc private func displaySettings() {
        let panel = UITableViewController(style: .insetGrouped)
        panel.preferredContentSize = CGSize(width: 310, height: 320)
        panel.modalPresentationStyle = .popover; panel.overrideUserInterfaceStyle = .dark
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 8; stack.frame = CGRect(x: 16, y: 16, width: 278, height: 280)
        let title = UILabel(); title.text = "보기 설정"; title.font = .systemFont(ofSize: 15, weight: .medium); title.textAlignment = .center; stack.addArrangedSubview(title)
        for (label, action) in [
            ("한 페이지씩", { self.provider.commitAll(); self.pdfView.displayMode = .singlePage; UserDefaults.standard.set(false, forKey: "inkdrive.continuous-pages") }),
            ("연속 페이지", { self.provider.commitAll(); self.pdfView.displayMode = .singlePageContinuous; UserDefaults.standard.set(true, forKey: "inkdrive.continuous-pages") }),
            ("화면에 맞추기", { self.needsInitialPageFit = true; self.view.setNeedsLayout() }),
            ("도구막대 가로·세로", { self.rotateToolbar() }),
            ("저장", { self.saveNow() })
        ] as [(String, () -> Void)] {
            let button = UIButton(type: .system); button.setTitle(label, for: .normal); button.contentHorizontalAlignment = .leading; button.titleLabel?.font = .systemFont(ofSize: 13); button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            button.addAction(UIAction { _ in action() }, for: .touchUpInside); stack.addArrangedSubview(button)
        }
        panel.view.addSubview(stack)
        panel.popoverPresentationController?.sourceView = view; panel.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.width - 66, y: view.safeAreaInsets.top + 34, width: 32, height: 1); panel.popoverPresentationController?.delegate = self
        present(panel, animated: true)
    }
    private func buildToolbar() {
        floating.accessibilityIdentifier = "ink-toolbar"
        floating.backgroundColor = .black; floating.layer.cornerRadius = 5
        floating.layer.borderWidth = 1; floating.layer.borderColor = UIColor(white: 0.25, alpha: 1).cgColor
        floating.layer.shadowColor = UIColor(hex: "#203653").cgColor; floating.layer.shadowOpacity = 0.25
        floating.layer.shadowRadius = 5; floating.layer.shadowOffset = CGSize(width: 0, height: 5)
        floating.frame = CGRect(x: 180, y: 120, width: 520, height: 44)
        if let position = UserDefaults.standard.array(forKey: "inkdrive.toolbar-position") as? [Double], position.count == 2 { floating.frame.origin = CGPoint(x: position[0], y: position[1]) }
        floating.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]; view.addSubview(floating)
        let stack = toolbarStack; stack.axis = toolbarVertical ? .vertical : .horizontal; stack.spacing = 0; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false; floating.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: floating.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: floating.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: floating.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: floating.trailingAnchor, constant: -6)])
        let handle = InkIcons.button("grip-vertical", label: "도구막대 이동", compact: true)
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragToolbar)))
        stack.addArrangedSubview(handle)
        toolScroll.showsHorizontalScrollIndicator = false
        toolScroll.showsVerticalScrollIndicator = false
        tools.axis = toolbarVertical ? .vertical : .horizontal; tools.spacing = 0; tools.translatesAutoresizingMaskIntoConstraints = false
        toolScroll.addSubview(tools)
        NSLayoutConstraint.activate([tools.leadingAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.trailingAnchor),
            tools.topAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.topAnchor),
            tools.bottomAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.bottomAnchor)])
        stack.addArrangedSubview(toolScroll)
        stack.addArrangedSubview(iconButton("undo-2", label: "실행 취소", action: #selector(undoAction)))
        stack.addArrangedSubview(iconButton("redo-2", label: "다시 실행", action: #selector(redoAction)))
        stack.addArrangedSubview(iconButton("plus", label: "도구 추가·빼기", action: #selector(manageTools)))
        stack.addArrangedSubview(iconButton("rotate-cw", label: "도구막대 방향 전환", action: #selector(rotateToolbar)))
        updateToolbarAxis()
        rebuildTools(); setTool(visibleTools.first ?? .pen)
    }
    private func rebuildTools() {
        tools.arrangedSubviews.forEach { tools.removeArrangedSubview($0); $0.removeFromSuperview() }
        toolButtons.removeAll()
        let presets = (UserDefaults.standard.array(forKey: "inkdrive.tool-presets.v2") as? [Data] ?? []).compactMap { try? JSONDecoder().decode(ToolPreset.self, from: $0) }
        for (index, preset) in presets.enumerated() {
            let item = InkIcons.button(preset.tool.icon, label: "즐겨찾기 \(index + 1), \(preset.settings.width) px", compact: true)
            item.setImage(PenNibArtwork.image(tool: preset.tool, color: preset.settings.uiColor.withAlphaComponent(1), width: preset.settings.width), for: .normal)
            item.tintColor = preset.settings.uiColor.withAlphaComponent(1)
            item.backgroundColor = preset.settings.uiColor.withAlphaComponent(0.08)
            item.addAction(UIAction { [weak self] _ in
                guard let self else { return }; self.configurations[preset.tool.rawValue] = preset.settings
                UserDefaults.standard.set(try? JSONEncoder().encode(self.configurations), forKey: "inkdrive.tools.v1"); self.setTool(preset.tool)
            }, for: .touchUpInside)
            item.menu = UIMenu(children: [UIAction(title: "즐겨찾기 삭제", attributes: .destructive) { [weak self] _ in
                var saved = UserDefaults.standard.array(forKey: "inkdrive.tool-presets.v2") as? [Data] ?? []
                guard saved.indices.contains(index) else { return }; saved.remove(at: index); UserDefaults.standard.set(saved, forKey: "inkdrive.tool-presets.v2"); self?.rebuildTools()
            }]); tools.addArrangedSubview(item)
        }
        for choice in visibleTools {
            let item = InkIcons.button(choice.icon, label: choice.label, compact: true)
            item.addAction(UIAction { [weak self, weak item] _ in
                guard let self, let item else { return }
                if self.tool == choice { self.showToolPopover(from: item) } else { self.setTool(choice) }
            }, for: .touchUpInside)
            toolButtons[choice] = item; tools.addArrangedSubview(item)
        }
        updateToolAppearance(); view.setNeedsLayout()
    }
    private func updateToolAppearance() {
        toolButtons.forEach { choice, item in
            let color = (configurations[choice.rawValue] ?? ToolSettings()).uiColor.withAlphaComponent(1)
            item.setImage(PenNibArtwork.image(tool: choice, color: color, width: (configurations[choice.rawValue] ?? ToolSettings()).width), for: .normal)
            item.tintColor = .white
            item.backgroundColor = choice == tool ? UIColor(white: 0.20, alpha: 1) : .clear
            item.layer.borderWidth = choice == tool ? 1 : 0
            item.layer.borderColor = color.withAlphaComponent(0.25).cgColor
            item.accessibilityValue = choice == tool ? "선택됨, 다시 누르면 설정" : nil
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let length = CGFloat(tools.arrangedSubviews.count * 36 + 192)
        floating.frame.size = toolbarVertical ? CGSize(width: 48, height: min(length, view.bounds.height - view.safeAreaInsets.top - 110)) : CGSize(width: min(length, view.bounds.width - 24), height: 48)
        floating.frame.origin.x = min(max(12, floating.frame.origin.x), max(12, view.bounds.width - floating.frame.width - 12))
        let minimumY = view.safeAreaInsets.top + (openDocument == nil ? 40 : 68)
        floating.frame.origin.y = min(max(minimumY, floating.frame.origin.y), max(minimumY, view.bounds.height - floating.frame.height - view.safeAreaInsets.bottom))
        viewport.configure(pdfView)
        if needsInitialPageFit, pdfView.bounds.width > 80, pdfView.bounds.height > 80,
           let page = pdfView.currentPage ?? session.model.pdf.page(at: 0) {
            needsInitialPageFit = false
            let crop = page.bounds(for: .cropBox)
            let rotated = page.rotation % 180 != 0
            let width = rotated ? crop.height : crop.width, height = rotated ? crop.width : crop.height
            let fit = min((pdfView.bounds.width - 48) / width, (pdfView.bounds.height - 32) / height)
            pdfView.autoScales = false; pdfView.minScaleFactor = fit * 0.4; pdfView.maxScaleFactor = max(6, fit * 6); pdfView.scaleFactor = fit
            pdfView.go(to: page)
        }
    }
    private func iconButton(_ icon: String, label: String, action: Selector) -> UIButton {
        let item = InkIcons.button(icon, label: label, compact: true); item.addTarget(self, action: action, for: .touchUpInside); return item
    }
    func setTool(_ new: EditorTool) {
        provider.commitAll()
        if tool != .eraser { previousTool = tool }
        tool = new
        if !visibleTools.contains(new) { visibleTools.append(new); persistVisibleTools(); rebuildTools() }
        updateToolAppearance(); provider.applyTool()
    }
    private func updateSettings(_ change: (inout ToolSettings) -> Void) {
        var value = settings; change(&value); configurations[tool.rawValue] = value
        UserDefaults.standard.set(try? JSONEncoder().encode(configurations), forKey: "inkdrive.tools.v1")
        updateToolAppearance(); provider.applyTool()
    }
    private func showToolPopover(from anchor: UIView) {
        let choice = tool
        let popover = ToolPopoverController(tool: choice, settings: settings) { [weak self] value in
            guard let self else { return }
            self.configurations[choice.rawValue] = value
            UserDefaults.standard.set(try? JSONEncoder().encode(self.configurations), forKey: "inkdrive.tools.v1")
            self.updateToolAppearance(); self.provider.applyTool()
        }
        popover.toolSelected = { [weak self] next in
            guard let self else { return }; self.setTool(next)
            if let button = self.toolButtons[next] { self.showToolPopover(from: button) }
        }
        popover.removeTool = { [weak self] in self?.hideTool(choice) }
        popover.advanced = { [weak self] in self?.toolOptions() }
        popover.popoverPresentationController?.sourceView = anchor
        popover.popoverPresentationController?.sourceRect = anchor.bounds
        popover.popoverPresentationController?.delegate = self
        present(popover, animated: true)
    }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) { rebuildTools() }
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }
    private func persistVisibleTools() { UserDefaults.standard.set(visibleTools.map(\.rawValue), forKey: "inkdrive.visible-tools.v2") }
    private func hideTool(_ choice: EditorTool) {
        guard visibleTools.count > 1 else { return }
        visibleTools.removeAll { $0 == choice }; persistVisibleTools()
        if tool == choice { tool = visibleTools[0] }
        rebuildTools(); provider.applyTool()
    }
    @objc private func manageTools() {
        let controller = UIViewController(); controller.modalPresentationStyle = .popover
        controller.preferredContentSize = CGSize(width: 252, height: 320); controller.view.backgroundColor = UIColor(white: 0.14, alpha: 1)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 6; stack.frame = CGRect(x: 16, y: 14, width: 220, height: 292); controller.view.addSubview(stack)
        for choice in EditorTool.allCases {
            let item = UIButton(type: .system)
            item.setImage(InkIcons.image(choice.icon), for: .normal)
            item.setTitle("  " + choice.label, for: .normal); item.contentHorizontalAlignment = .leading
            item.tintColor = UIColor(white: 0.88, alpha: 1); item.layer.cornerRadius = 10
            item.backgroundColor = visibleTools.contains(choice) ? UIColor(white: 0.25, alpha: 1) : UIColor(white: 0.17, alpha: 1)
            item.accessibilityValue = visibleTools.contains(choice) ? "추가됨" : "숨겨짐"
            item.heightAnchor.constraint(equalToConstant: 44).isActive = true
            item.addAction(UIAction { [weak self, weak item] _ in
                guard let self else { return }
                if self.visibleTools.contains(choice) { self.hideTool(choice) }
                else { self.visibleTools.append(choice); self.persistVisibleTools(); self.rebuildTools() }
                item?.backgroundColor = self.visibleTools.contains(choice) ? UIColor(white: 0.25, alpha: 1) : UIColor(white: 0.17, alpha: 1)
                item?.accessibilityValue = self.visibleTools.contains(choice) ? "추가됨" : "숨겨짐"
            }, for: .touchUpInside)
            stack.addArrangedSubview(item)
        }
        controller.popoverPresentationController?.sourceView = floating
        controller.popoverPresentationController?.sourceRect = CGRect(x: floating.bounds.maxX - 50, y: 0, width: 44, height: 44)
        controller.popoverPresentationController?.delegate = self
        present(controller, animated: true)
    }
    @objc private func dragToolbar(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: view); floating.center.x += delta.x; floating.center.y += delta.y
        gesture.setTranslation(.zero, in: view); viewDidLayoutSubviews()
        if gesture.state == .ended { UserDefaults.standard.set([Double(floating.frame.origin.x), Double(floating.frame.origin.y)], forKey: "inkdrive.toolbar-position") }
    }
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .ignore: break
        case .showColorPalette: if let anchor = toolButtons[tool] { showToolPopover(from: anchor) }
        case .switchPrevious: setTool(previousTool)
        default: setTool(tool == .eraser ? previousTool : .eraser)
        }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func undoAction() { provider.commitAll(); session.history.undo(); refresh() }
    @objc private func redoAction() { provider.commitAll(); session.history.redo(); refresh() }
    private func refresh() {
        if pdfView.document !== session.model.pdf {
            provider.overlays.removeAll(); pdfView.document = session.model.pdf
        }
        provider.refreshAll(); pdfView.setNeedsDisplay()
    }
    @objc private func saveNow() {
        provider.commitAll(); Task { do { try await session.flush() } catch { showError(error) } }
    }
    @objc private func closeEditor() {
        guard !closing, !switchingDocument, !startingRecording else { return }
        closing = true; view.isUserInteractionEnabled = false
        recordingBrowser?.shutdown(); recordingBrowser = nil; recordingStrip.isHidden = true
        Task {
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
                provider.commitAll()
                try await session.flush()
                dismiss(animated: true) { [didClose] in didClose?() }
            } catch { closing = false; view.isUserInteractionEnabled = true; showError(error) }
        }
    }
    private func backgroundSave() {
        provider.commitAll()
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "InkDrive save") { [weak self] in
            self?.status.text = "백그라운드 저장 시간 제한 · 다시 열어 저장 상태를 확인해 주세요"
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
        Task {
            do { try await session.flush() } catch { status.text = error.localizedDescription }
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
    }
    func showError(_ error: Error) {
        status.text = error.localizedDescription
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "작업을 완료하지 못했어요", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default)); present(alert, animated: true)
    }
    func menu(_ title: String, actions: [(String, () -> Void)]) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        actions.forEach { name, action in sheet.addAction(UIAlertAction(title: name, style: .default) { _ in action() }) }
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        sheet.popoverPresentationController?.sourceView = floating
        sheet.popoverPresentationController?.sourceRect = floating.bounds
        present(sheet, animated: true)
    }
    @objc private func toolOptions() {
        var actions: [(String, () -> Void)] = [
            ("현재 설정 즐겨찾기 저장", { self.savePreset() }),
            ("즐겨찾기 불러오기", { self.loadPreset() }),
            ("필기 붙여넣기", {
                guard let page = self.pdfView.currentPage, let record = self.session.model.record(for: page),
                      let overlay = self.provider.overlays[record.id] else { return }
                overlay.interaction.paste()
            })
        ]
        if tool == .eraser {
            actions += [
                (settings.partialEraser ? "획 지우개로 전환" : "부분 지우개로 전환", { self.updateSettings { $0.partialEraser.toggle() } }),
                (settings.returnToPen ? "지운 뒤 도구 유지" : "지운 뒤 펜으로 복귀", { self.updateSettings { $0.returnToPen.toggle() } }),
                ("지우개 대상: 전체 필기", { self.updateSettings { $0.eraserTarget = "all" } }),
                ("지우개 대상: 펜·연필 획", { self.updateSettings { $0.eraserTarget = "pen" } }),
                ("지우개 대상: 형광펜 획", { self.updateSettings { $0.eraserTarget = "marker" } })
            ]
        }
        if tool == .marker { actions.append((settings.markerStraight ? "형광펜 자유선" : "형광펜 직선 모드", { self.updateSettings { $0.markerStraight.toggle() } })) }
        if tool == .text { actions.append(("글꼴·정렬", { self.textOptions() })) }
        menu("도구 설정 · 도구마다 기억해요", actions: actions)
    }
    private func textOptions() {
        menu("텍스트 설정", actions: [
            ("기본 글꼴", { self.updateSettings { $0.font = "system" } }),
            ("Helvetica", { self.updateSettings { $0.font = "Helvetica" } }),
            ("세리프 글꼴", { self.updateSettings { $0.font = "serif" } }),
            ("고정폭 글꼴", { self.updateSettings { $0.font = "mono" } }),
            ("굵게 전환", { self.updateSettings { $0.textTraits = ($0.textTraits ?? 0) ^ UIFontDescriptor.SymbolicTraits.traitBold.rawValue } }),
            ("기울임 전환", { self.updateSettings { $0.textTraits = ($0.textTraits ?? 0) ^ UIFontDescriptor.SymbolicTraits.traitItalic.rawValue } }),
            ("왼쪽 정렬", { self.updateSettings { $0.alignment = NSTextAlignment.left.rawValue } }),
            ("가운데 정렬", { self.updateSettings { $0.alignment = NSTextAlignment.center.rawValue } }),
            ("오른쪽 정렬", { self.updateSettings { $0.alignment = NSTextAlignment.right.rawValue } })
        ])
    }
    private func savePreset() {
        var presets = UserDefaults.standard.array(forKey: "inkdrive.presets") as? [Data] ?? []
        if let bytes = try? JSONEncoder().encode(settings) { presets.append(bytes) }
        UserDefaults.standard.set(Array(presets.suffix(12)), forKey: "inkdrive.presets")
        var typed = UserDefaults.standard.array(forKey: "inkdrive.tool-presets.v2") as? [Data] ?? []
        if let bytes = try? JSONEncoder().encode(ToolPreset(tool: tool, settings: settings)) { typed.append(bytes) }
        UserDefaults.standard.set(Array(typed.suffix(8)), forKey: "inkdrive.tool-presets.v2"); rebuildTools()
    }
    private func loadPreset() {
        let presets = (UserDefaults.standard.array(forKey: "inkdrive.presets") as? [Data] ?? []).compactMap { try? JSONDecoder().decode(ToolSettings.self, from: $0) }
        menu("즐겨찾기", actions: presets.enumerated().map { i, value in
            ("\(i + 1) · \(value.color) · \(value.width) px", { self.configurations[self.tool.rawValue] = value; self.setTool(self.tool) })
        })
    }
    func selectionMenu(_ selection: StrokeInteractionView) {
        guard presentedViewController == nil else { return }
        let controller = SelectionPopoverController(selection: selection, width: settings.width)
        controller.popoverPresentationController?.sourceView = selection
        controller.popoverPresentationController?.sourceRect = selection.selectedBounds
        controller.popoverPresentationController?.passthroughViews = [selection]
        controller.popoverPresentationController?.delegate = self
        present(controller, animated: true)
    }
    private func pagePoint(_ point: CGPoint, record: NotebookPage) -> CGPoint {
        let crop = record.page.bounds(for: .cropBox)
        return CGPoint(x: crop.minX + point.x, y: crop.maxY - point.y)
    }
    func textGesture(record: NotebookPage, from start: CGPoint, to end: CGPoint) {
        let point = pagePoint(start, record: record)
        let existing = record.page.annotations.last { $0.bounds.contains(point) && $0.value(forAnnotationKey: PDFAnnotationKey(rawValue: "InkDriveEditable")) as? String == "v1" }
        if let existing, hypot(end.x - start.x, end.y - start.y) > 5 {
            guard let moved = existing.copy() as? PDFAnnotation else { return }
            moved.bounds = existing.bounds.offsetBy(dx: end.x - start.x, dy: start.y - end.y)
            session.replaceAnnotation(existing, with: moved, pageID: record.id); return
        }
        if let existing {
            menu("선택한 주석", actions: [
                ("텍스트·크기 수정", { self.editText(record: record, point: point, existing: existing) }),
                ("삭제", { self.session.removeAnnotation(existing, pageID: record.id) })
            ])
        } else { editText(record: record, point: point, existing: nil) }
    }
    private func editText(record: NotebookPage, point: CGPoint, existing: PDFAnnotation?) {
        if let existing, existing.type != PDFAnnotationSubtype.freeText.rawValue { return }
        let alert = UIAlertController(title: "텍스트 상자", message: "Pencil로 드래그하면 위치를 옮길 수 있어요.", preferredStyle: .alert)
        let pointSize: CGFloat = existing?.font?.pointSize ?? CGFloat(settings.fontSize)
        let boxWidth: CGFloat = existing?.bounds.width ?? 240
        let boxHeight: CGFloat = existing?.bounds.height ?? 100
        let textFields: [(String, String)] = [
            ("내용", existing?.contents ?? ""), ("글자 크기", String(Double(pointSize))),
            ("상자 너비", String(Double(boxWidth))), ("상자 높이", String(Double(boxHeight)))
        ]
        for (placeholder, value) in textFields {
            alert.addTextField { $0.placeholder = placeholder; $0.text = value }
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "적용", style: .default) { _ in
            guard let fields = alert.textFields, let size = Double(fields[1].text ?? ""), (6...144).contains(size),
                  let width = Double(fields[2].text ?? ""), (20...2000).contains(width),
                  let height = Double(fields[3].text ?? ""), (20...2000).contains(height) else { self.showError(InkError.invalidName); return }
            let bounds = CGRect(x: existing?.bounds.minX ?? point.x, y: existing?.bounds.minY ?? point.y - height, width: width, height: height)
            let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
            annotation.contents = fields[0].text; annotation.font = self.settings.uiFont.withSize(size)
            annotation.fontColor = self.settings.uiColor; annotation.color = .clear
            annotation.alignment = NSTextAlignment(rawValue: self.settings.alignment) ?? .left
            annotation.setValue("v1", forAnnotationKey: PDFAnnotationKey(rawValue: "InkDriveEditable"))
            if let existing { self.session.replaceAnnotation(existing, with: annotation, pageID: record.id) }
            else { self.session.addAnnotation(annotation, pageID: record.id) }
        })
        present(alert, animated: true)
    }
    @objc private func showPages() {
        provider.commitAll()
        let pages = PageOverviewController(editor: self)
        let navigation = UINavigationController(rootViewController: pages); navigation.modalPresentationStyle = .fullScreen; navigation.overrideUserInterfaceStyle = .dark
        present(navigation, animated: true)
    }
    @objc private func more() {
        menu("문서", actions: [
            ("외부 버전 다시 열기", { self.confirmReload() }),
            ("현재 편집 PDF 공유·복구 사본", { self.shareSnapshot() })
        ])
    }
    private func confirmReload() {
        let alert = UIAlertController(title: "외부 버전을 다시 열까요?", message: "이 화면의 미저장 변경은 버려져요. 필요하면 먼저 복구 사본을 저장해 주세요.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "미저장 변경 버리고 다시 열기", style: .destructive) { _ in
            self.view.isUserInteractionEnabled = false
            Task {
                defer { self.view.isUserInteractionEnabled = true }
                do { try await self.session.reloadDiscardingChanges() } catch { self.showError(error) }
            }
        }); present(alert, animated: true)
    }
    private func shareSnapshot() {
        do {
            provider.commitAll()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("InkDrive-\(UUID().uuidString).pdf")
            try session.model.snapshot().write(to: url, options: .atomic)
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            controller.popoverPresentationController?.sourceView = floating
            controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
            present(controller, animated: true)
        } catch { showError(error) }
    }
}
