import UIKit
import PDFKit
import PencilKit

@MainActor final class EditorViewController: UIViewController, UIPencilInteractionDelegate, UIGestureRecognizerDelegate {
    let session: EditorSession
    let pdfView = PDFView()
    let provider = OverlayProvider()
    private(set) var tool: EditorTool = .pen
    private var previousTool: EditorTool = .pen
    private var configurations: [String: ToolSettings] = [:]
    var settings: ToolSettings { configurations[tool.rawValue] ?? ToolSettings() }
    private let floating = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let tools = UIStackView()
    private let status = UILabel()
    private let width = UISlider(), opacity = UISlider(), color = UIColorWell()
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
        if let bytes = UserDefaults.standard.data(forKey: "inkdrive.tools.v1"),
           let decoded = try? JSONDecoder().decode([String: ToolSettings].self, from: bytes) { configurations = decoded }
        if configurations[EditorTool.marker.rawValue] == nil {
            var marker = ToolSettings(); marker.color = "#FFE247"; marker.width = 18; marker.opacity = 0.45
            configurations[EditorTool.marker.rawValue] = marker
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = UIColor(white: 0.94, alpha: 1)
        provider.editor = self
        pdfView.pageOverlayViewProvider = provider
        pdfView.document = session.model.pdf
        pdfView.displayMode = .singlePageContinuous; pdfView.displayDirection = .vertical
        pdfView.displayBox = .cropBox; pdfView.autoScales = true; pdfView.pageShadowsEnabled = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(pdfView)
        let header = UIStackView(); header.spacing = 12; header.alignment = .center
        header.addArrangedSubview(button("닫기", action: #selector(closeEditor)))
        status.text = "원본 열림 · Pencil로 필기"; status.font = .systemFont(ofSize: 12); status.numberOfLines = 2
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(status)
        recordingLabel.textColor = .systemRed; recordingLabel.font = .systemFont(ofSize: 11); recordingLabel.numberOfLines = 2
        header.addArrangedSubview(recordingLabel)
        let stopRecording = button("녹음 종료", action: #selector(stopAudioRecording)); header.addArrangedSubview(stopRecording)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak stopRecording] _ in
            Task { @MainActor in
                let service = RecordingService.shared
                self?.recordingLabel.isHidden = !service.active
                stopRecording?.isHidden = !service.active
                self?.recordingLabel.text = "● 녹음 중\n\(Int(service.seconds / 60))분"
            }
        }
        recordingLabel.isHidden = !RecordingService.shared.active; stopRecording.isHidden = !RecordingService.shared.active
        header.addArrangedSubview(button("페이지", action: #selector(showPages)))
        header.addArrangedSubview(button("저장", action: #selector(saveNow)))
        header.addArrangedSubview(button("더보기", action: #selector(more)))
        header.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), header.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            pdfView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6), pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor), pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        buildToolbar()
        let pencil = UIPencilInteraction(); pencil.delegate = self; view.addInteraction(pencil)
        let undo = UITapGestureRecognizer(target: self, action: #selector(undoAction))
        undo.numberOfTouchesRequired = 2; undo.numberOfTapsRequired = 2; undo.delegate = self
        undo.cancelsTouchesInView = false; pdfView.addGestureRecognizer(undo)
        session.didChange = { [weak self] in self?.refresh() }
        session.statusChanged = { [weak self] value in self?.status.text = value }
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
    deinit { observerTokens.forEach(NotificationCenter.default.removeObserver); recordingTimer?.invalidate() }
    @objc private func stopAudioRecording() {
        Task { do { try await RecordingService.shared.stop() } catch { showError(error) } }
    }
    private func buildToolbar() {
        floating.layer.cornerRadius = 16; floating.clipsToBounds = true
        floating.frame = CGRect(x: 20, y: 110, width: min(730, view.bounds.width - 40), height: 146)
        floating.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]; view.addSubview(floating)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; floating.contentView.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: floating.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: floating.contentView.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: floating.contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: floating.contentView.trailingAnchor, constant: -10)])
        let handle = UILabel(); handle.text = "⋮⋮  도구 막대 이동"; handle.textAlignment = .center; handle.font = .systemFont(ofSize: 11)
        handle.isUserInteractionEnabled = true; handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragToolbar)))
        stack.addArrangedSubview(handle)
        toolScroll.showsHorizontalScrollIndicator = true; toolScroll.heightAnchor.constraint(equalToConstant: 42).isActive = true
        tools.axis = .horizontal; tools.spacing = 5; tools.translatesAutoresizingMaskIntoConstraints = false
        toolScroll.addSubview(tools)
        NSLayoutConstraint.activate([tools.leadingAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.trailingAnchor),
            tools.topAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.topAnchor),
            tools.bottomAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.bottomAnchor),
            tools.heightAnchor.constraint(equalTo: toolScroll.frameLayoutGuide.heightAnchor)])
        let labels: [EditorTool: String] = [.pen:"펜", .pencil:"연필", .marker:"형광펜", .eraser:"지우개", .lasso:"올가미", .text:"텍스트", .line:"직선", .rectangle:"사각형", .ellipse:"타원", .hand:"이동"]
        for choice in EditorTool.allCases {
            let item = UIButton(type: .system); item.setTitle(labels[choice], for: .normal)
            item.addAction(UIAction { [weak self] _ in self?.setTool(choice) }, for: .touchUpInside)
            item.accessibilityLabel = labels[choice]; item.widthAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
            toolButtons[choice] = item; tools.addArrangedSubview(item)
        }
        stack.addArrangedSubview(toolScroll)
        let controls = UIStackView(); controls.spacing = 10; controls.alignment = .center
        color.supportsAlpha = false; color.addTarget(self, action: #selector(changeColor), for: .valueChanged)
        color.widthAnchor.constraint(equalToConstant: 36).isActive = true; controls.addArrangedSubview(color)
        let widthLabel = UILabel(); widthLabel.text = "굵기"; widthLabel.font = .systemFont(ofSize: 12); controls.addArrangedSubview(widthLabel)
        width.minimumValue = 0.5; width.maximumValue = 40; width.accessibilityLabel = "굵기"
        width.addTarget(self, action: #selector(changeWidth), for: .valueChanged); controls.addArrangedSubview(width)
        let alphaLabel = UILabel(); alphaLabel.text = "불투명도"; alphaLabel.font = .systemFont(ofSize: 12); controls.addArrangedSubview(alphaLabel)
        opacity.minimumValue = 0.05; opacity.maximumValue = 1; opacity.accessibilityLabel = "불투명도"
        opacity.addTarget(self, action: #selector(changeOpacity), for: .valueChanged); controls.addArrangedSubview(opacity)
        controls.addArrangedSubview(button("↶", action: #selector(undoAction)))
        controls.addArrangedSubview(button("↷", action: #selector(redoAction)))
        controls.addArrangedSubview(button("설정", action: #selector(toolOptions)))
        stack.addArrangedSubview(controls); setTool(.pen)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        floating.frame.size.width = min(730, view.bounds.width - 24)
        floating.frame.origin.x = min(max(12, floating.frame.origin.x), max(12, view.bounds.width - floating.frame.width - 12))
        floating.frame.origin.y = min(max(view.safeAreaInsets.top + 56, floating.frame.origin.y), max(view.safeAreaInsets.top + 56, view.bounds.height - floating.frame.height - view.safeAreaInsets.bottom))
    }
    private func button(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system); button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        return button
    }
    func setTool(_ new: EditorTool) {
        provider.commitAll()
        if tool != .eraser && tool != .hand { previousTool = tool }
        tool = new
        toolButtons.forEach { choice, button in
            button.backgroundColor = choice == new ? UIColor.systemBlue.withAlphaComponent(0.12) : .clear
            button.layer.cornerRadius = 7; button.accessibilityValue = choice == new ? "선택됨" : nil
        }
        color.selectedColor = settings.uiColor
        width.value = Float(new == .eraser ? settings.eraserWidth : settings.width)
        opacity.value = Float(settings.opacity)
        provider.applyTool()
    }
    private func updateSettings(_ change: (inout ToolSettings) -> Void) {
        var value = settings; change(&value); configurations[tool.rawValue] = value
        UserDefaults.standard.set(try? JSONEncoder().encode(configurations), forKey: "inkdrive.tools.v1")
        provider.applyTool()
    }
    @objc private func changeColor() { updateSettings { $0.color = (color.selectedColor ?? .blue).hexString } }
    @objc private func changeWidth() { updateSettings { if tool == .eraser { $0.eraserWidth = Double(width.value) } else { $0.width = Double(width.value) } } }
    @objc private func changeOpacity() { updateSettings { $0.opacity = Double(opacity.value) } }
    @objc private func dragToolbar(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: view); floating.center.x += delta.x; floating.center.y += delta.y
        gesture.setTranslation(.zero, in: view); viewDidLayoutSubviews()
    }
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        switch UIPencilInteraction.preferredTapAction {
        case .ignore: break
        case .showColorPalette: toolOptions()
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
        guard !closing else { return }
        closing = true; view.isUserInteractionEnabled = false
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
        if tool == .rectangle || tool == .ellipse { actions.append((settings.fillShape ? "채우기 끄기" : "채우기 켜기", { self.updateSettings { $0.fillShape.toggle() } })) }
        menu("도구 설정 · 도구마다 기억해요", actions: actions)
    }
    private func textOptions() {
        menu("텍스트 설정", actions: [
            ("기본 글꼴", { self.updateSettings { $0.font = "system" } }),
            ("세리프 글꼴", { self.updateSettings { $0.font = "serif" } }),
            ("고정폭 글꼴", { self.updateSettings { $0.font = "mono" } }),
            ("왼쪽 정렬", { self.updateSettings { $0.alignment = NSTextAlignment.left.rawValue } }),
            ("가운데 정렬", { self.updateSettings { $0.alignment = NSTextAlignment.center.rawValue } }),
            ("오른쪽 정렬", { self.updateSettings { $0.alignment = NSTextAlignment.right.rawValue } })
        ])
    }
    private func savePreset() {
        var presets = UserDefaults.standard.array(forKey: "inkdrive.presets") as? [Data] ?? []
        if let bytes = try? JSONEncoder().encode(settings) { presets.append(bytes) }
        UserDefaults.standard.set(Array(presets.suffix(12)), forKey: "inkdrive.presets")
    }
    private func loadPreset() {
        let presets = (UserDefaults.standard.array(forKey: "inkdrive.presets") as? [Data] ?? []).compactMap { try? JSONDecoder().decode(ToolSettings.self, from: $0) }
        menu("즐겨찾기", actions: presets.enumerated().map { i, value in
            ("\(i + 1) · \(value.color) · \(value.width)pt", { self.configurations[self.tool.rawValue] = value; self.setTool(self.tool) })
        })
    }
    func selectionMenu(_ selection: StrokeInteractionView) {
        menu("선택한 획 · 선택 테두리를 드래그하면 이동", actions: [
            ("복사", { selection.copySelection() }), ("잘라내기", { selection.copySelection(); selection.deleteSelection() }),
            ("붙여넣기", { selection.paste() }), ("삭제", { selection.deleteSelection() }),
            ("현재 색상 적용", { selection.recolor(self.settings.uiColor) }),
            ("현재 굵기 적용", { selection.rewidth(self.settings.width) }),
            ("크기 120%", { selection.scaleSelection(1.2) }), ("크기 80%", { selection.scaleSelection(0.8) })
        ])
    }
    private func pagePoint(_ point: CGPoint, record: NotebookPage) -> CGPoint {
        let crop = record.page.bounds(for: .cropBox)
        return CGPoint(x: crop.minX + point.x, y: crop.maxY - point.y)
    }
    func addShape(record: NotebookPage, from start: CGPoint, to end: CGPoint) {
        guard hypot(end.x - start.x, end.y - start.y) >= 2 else { return }
        let first = pagePoint(start, record: record), last = pagePoint(end, record: record)
        let bounds = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: max(1, abs(last.x - first.x)), height: max(1, abs(last.y - first.y)))
        let type: PDFAnnotationSubtype = tool == .rectangle ? .square : tool == .ellipse ? .circle : .line
        let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
        annotation.color = settings.uiColor; let border = PDFBorder(); border.lineWidth = settings.width; annotation.border = border
        if type == .line { annotation.startPoint = CGPoint(x: first.x - bounds.minX, y: first.y - bounds.minY); annotation.endPoint = CGPoint(x: last.x - bounds.minX, y: last.y - bounds.minY) }
        else if settings.fillShape { annotation.interiorColor = settings.uiColor.withAlphaComponent(settings.opacity * 0.25) }
        annotation.setValue("v1", forAnnotationKey: PDFAnnotationKey(rawValue: "InkDriveEditable"))
        session.addAnnotation(annotation, pageID: record.id)
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
        let pages = PageListController(editor: self)
        let navigation = UINavigationController(rootViewController: pages); navigation.modalPresentationStyle = .pageSheet
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
