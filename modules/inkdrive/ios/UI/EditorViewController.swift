import UIKit
import PDFKit
import PencilKit

@MainActor final class EditorViewController: UIViewController, UIPencilInteractionDelegate, UIGestureRecognizerDelegate, UIPopoverPresentationControllerDelegate {
    let session: EditorSession
    let pdfView = PDFView()
    let provider = OverlayProvider()
    private(set) var tool: EditorTool = .pen
    private var previousTool: EditorTool = .pen
    private var configurations: [String: ToolSettings] = [:]
    var settings: ToolSettings { configurations[tool.rawValue] ?? ToolSettings() }
    private let floating = UIView()
    private let viewport = NotebookViewport()
    private var visibleTools: [EditorTool] = EditorTool.allCases
    private let recordButton = UIButton(type: .system)
    var recordingAction: (() async throws -> Void)?
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
        if configurations[EditorTool.marker.rawValue] == nil {
            var marker = ToolSettings(); marker.color = "#FFE247"; marker.width = 18; marker.opacity = 0.45
            configurations[EditorTool.marker.rawValue] = marker
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = UIColor(white: 0.94, alpha: 1)
        provider.editor = self
        pdfView.isInMarkupMode = true
        pdfView.pageOverlayViewProvider = provider
        pdfView.document = session.model.pdf
        pdfView.displayMode = .singlePageContinuous; pdfView.displayDirection = .vertical
        pdfView.displayBox = .cropBox; pdfView.autoScales = true; pdfView.pageShadowsEnabled = true
        pdfView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(pdfView)
        let header = UIStackView(); header.spacing = 12; header.alignment = .center
        header.addArrangedSubview(iconButton("arrow-left", label: "서재로", action: #selector(closeEditor)))
        status.text = session.store.url.deletingPathExtension().lastPathComponent; status.font = .systemFont(ofSize: 14, weight: .medium); status.numberOfLines = 1; status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(status)
        recordButton.accessibilityLabel = "녹음 시작"
        recordButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        recordButton.layer.cornerRadius = 13; recordButton.backgroundColor = UIColor(hex: "#FFF0F1")
        recordButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        recordButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92).isActive = true
        recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
        header.addArrangedSubview(recordButton)
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRecordingButton() }
        }
        refreshRecordingButton()
        header.addArrangedSubview(iconButton("layers", label: "페이지", action: #selector(showPages)))
        header.addArrangedSubview(iconButton("save", label: "저장", action: #selector(saveNow)))
        header.addArrangedSubview(iconButton("ellipsis", label: "문서 메뉴", action: #selector(more)))
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
        session.statusChanged = { [weak self] value in self?.status.accessibilityValue = value }
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
    private func refreshRecordingButton() {
        let service = RecordingService.shared
        recordButton.isEnabled = !startingRecording
        recordButton.tintColor = UIColor(hex: "#CA4759")
        recordButton.setImage(InkIcons.image(service.active ? "square" : "mic"), for: .normal)
        let elapsed = Int(service.seconds)
        recordButton.setTitle(service.active ? String(format: "  %02d:%02d", elapsed / 60, elapsed % 60) : "  녹음", for: .normal)
        recordButton.accessibilityLabel = service.active ? "녹음 종료" : "녹음 시작"
        recordButton.accessibilityValue = service.active ? "녹음 중" : nil
    }
    @objc private func toggleRecording() {
        guard !startingRecording else { return }
        startingRecording = true; refreshRecordingButton()
        Task {
            defer { startingRecording = false; refreshRecordingButton() }
            do {
                if RecordingService.shared.active { try await RecordingService.shared.stop() }
                else {
                    guard canRecord, let recordingAction else {
                        throw NSError(domain: "InkDrive", code: 5, userInfo: [NSLocalizedDescriptionKey: "서재의 PDF를 열면 바로 녹음할 수 있어요."])
                    }
                    try await recordingAction()
                }
            } catch {
                let alert = UIAlertController(title: "녹음을 시작하지 못했어요", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "설정", style: .default) { _ in
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                })
                alert.addAction(UIAlertAction(title: "확인", style: .cancel))
                present(alert, animated: true)
            }
        }
    }
    private func buildToolbar() {
        floating.backgroundColor = .white; floating.layer.cornerRadius = 18
        floating.layer.borderWidth = 1; floating.layer.borderColor = UIColor(hex: "#E1E7F0").cgColor
        floating.layer.shadowColor = UIColor(hex: "#203653").cgColor; floating.layer.shadowOpacity = 0.08
        floating.layer.shadowRadius = 16; floating.layer.shadowOffset = CGSize(width: 0, height: 5)
        floating.frame = CGRect(x: 20, y: 110, width: 520, height: 56)
        floating.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]; view.addSubview(floating)
        let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 4; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false; floating.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: floating.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: floating.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: floating.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: floating.trailingAnchor, constant: -6)])
        let handle = InkIcons.button("grip-vertical", label: "도구막대 이동")
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragToolbar)))
        stack.addArrangedSubview(handle)
        toolScroll.showsHorizontalScrollIndicator = false
        toolScroll.heightAnchor.constraint(equalToConstant: 44).isActive = true
        tools.axis = .horizontal; tools.spacing = 4; tools.translatesAutoresizingMaskIntoConstraints = false
        toolScroll.addSubview(tools)
        NSLayoutConstraint.activate([tools.leadingAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.leadingAnchor),
            tools.trailingAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.trailingAnchor),
            tools.topAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.topAnchor),
            tools.bottomAnchor.constraint(equalTo: toolScroll.contentLayoutGuide.bottomAnchor),
            tools.heightAnchor.constraint(equalTo: toolScroll.frameLayoutGuide.heightAnchor)])
        stack.addArrangedSubview(toolScroll)
        stack.addArrangedSubview(iconButton("undo-2", label: "실행 취소", action: #selector(undoAction)))
        stack.addArrangedSubview(iconButton("redo-2", label: "다시 실행", action: #selector(redoAction)))
        stack.addArrangedSubview(iconButton("plus", label: "도구 추가·빼기", action: #selector(manageTools)))
        rebuildTools(); setTool(visibleTools.first ?? .pen)
    }
    private func rebuildTools() {
        tools.arrangedSubviews.forEach { tools.removeArrangedSubview($0); $0.removeFromSuperview() }
        toolButtons.removeAll()
        for choice in visibleTools {
            let item = InkIcons.button(choice.icon, label: choice.label)
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
            item.tintColor = color
            item.backgroundColor = choice == tool ? color.withAlphaComponent(0.12) : .clear
            item.layer.borderWidth = choice == tool ? 1 : 0
            item.layer.borderColor = color.withAlphaComponent(0.25).cgColor
            item.accessibilityValue = choice == tool ? "선택됨, 다시 누르면 설정" : nil
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        floating.frame.size.width = min(CGFloat(visibleTools.count * 48 + 212), view.bounds.width - 24)
        floating.frame.origin.x = min(max(12, floating.frame.origin.x), max(12, view.bounds.width - floating.frame.width - 12))
        floating.frame.origin.y = min(max(view.safeAreaInsets.top + 56, floating.frame.origin.y), max(view.safeAreaInsets.top + 56, view.bounds.height - floating.frame.height - view.safeAreaInsets.bottom))
        viewport.configure(pdfView)
    }
    private func iconButton(_ icon: String, label: String, action: Selector) -> UIButton {
        let item = InkIcons.button(icon, label: label); item.addTarget(self, action: action, for: .touchUpInside); return item
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
        popover.removeTool = { [weak self] in self?.hideTool(choice) }
        popover.advanced = { [weak self] in self?.toolOptions() }
        popover.popoverPresentationController?.sourceView = anchor
        popover.popoverPresentationController?.sourceRect = anchor.bounds
        popover.popoverPresentationController?.delegate = self
        present(popover, animated: true)
    }
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
        controller.preferredContentSize = CGSize(width: 252, height: 320); controller.view.backgroundColor = .white
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 6; stack.frame = CGRect(x: 16, y: 14, width: 220, height: 292); controller.view.addSubview(stack)
        for choice in EditorTool.allCases {
            let item = UIButton(type: .system)
            item.setImage(InkIcons.image(choice.icon), for: .normal)
            item.setTitle("  " + choice.label, for: .normal); item.contentHorizontalAlignment = .leading
            item.tintColor = UIColor(hex: "#34465D"); item.layer.cornerRadius = 10
            item.backgroundColor = visibleTools.contains(choice) ? UIColor(hex: "#EAF0FC") : UIColor(hex: "#F6F7FA")
            item.accessibilityValue = visibleTools.contains(choice) ? "추가됨" : "숨겨짐"
            item.heightAnchor.constraint(equalToConstant: 44).isActive = true
            item.addAction(UIAction { [weak self, weak item] _ in
                guard let self else { return }
                if self.visibleTools.contains(choice) { self.hideTool(choice) }
                else { self.visibleTools.append(choice); self.persistVisibleTools(); self.rebuildTools() }
                item?.backgroundColor = self.visibleTools.contains(choice) ? UIColor(hex: "#EAF0FC") : UIColor(hex: "#F6F7FA")
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
