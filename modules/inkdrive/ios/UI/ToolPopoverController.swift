import UIKit

@MainActor final class ToolPopoverController: UIViewController {
    private let tool: EditorTool
    private var settings: ToolSettings
    private let changed: (ToolSettings) -> Void
    var removeTool: (() -> Void)?
    var advanced: (() -> Void)?
    var toolSelected: ((EditorTool) -> Void)?
    init(tool: EditorTool, settings: ToolSettings, changed: @escaping (ToolSettings) -> Void) {
        self.tool = tool; self.settings = settings; self.changed = changed
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        preferredContentSize = CGSize(width: 280, height: tool == .eraser ? 420 : tool == .lasso ? 180 : tool == .marker ? 560 : 520)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = UIColor(white: 0.135, alpha: 1); overrideUserInterfaceStyle = .dark; view.tintColor = UIColor(hex: "#E8C65A")
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18)])
        let header = UIStackView(); header.alignment = .center
        let title = UILabel(); title.text = tool.label; title.font = .systemFont(ofSize: 16, weight: .semibold); header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        let hide = InkIcons.button("minus", label: "도구막대에서 빼기")
        hide.addAction(UIAction { [weak self] _ in guard let self else { return }; let action = self.removeTool; self.dismiss(animated: true, completion: action) }, for: .touchUpInside)
        header.addArrangedSubview(hide); stack.addArrangedSubview(header)
        if tool != .eraser && tool != .lasso {
            let nibs = UIStackView(); nibs.distribution = .fillEqually
            for choice in [EditorTool.pen, .pencil, .marker] {
                let nib = UIButton(type: .system); nib.setImage(PenNibArtwork.image(tool: choice, color: choice == tool ? settings.uiColor.withAlphaComponent(1) : UIColor(white: 0.35, alpha: 1), width: settings.width), for: .normal)
                nib.heightAnchor.constraint(equalToConstant: 48).isActive = true; nib.accessibilityLabel = choice.label + " 종류 선택"
                nib.addAction(UIAction { [weak self] _ in guard let self, choice != self.tool else { return }; self.dismiss(animated: false) { self.toolSelected?(choice) } }, for: .touchUpInside)
                nibs.addArrangedSubview(nib)
            }
            stack.addArrangedSubview(nibs)
            let paletteTitle = UILabel(); paletteTitle.text = "기본 색상"; paletteTitle.font = .systemFont(ofSize: 11); paletteTitle.textColor = .secondaryLabel; stack.addArrangedSubview(paletteTitle)
            let swatches = UIStackView(); swatches.distribution = .fillEqually; swatches.spacing = 0
            for hex in ["#E60012", "#F17B00", "#F3C800", "#63D538", "#33CBAA", "#22BDED", "#2455D6", "#6229D5", "#B308E0", "#747474", "#FFFFFF", "#111111"] {
                let dot = InkColorButton(type: .custom); dot.backgroundColor = UIColor(hex: hex); dot.layer.cornerRadius = 0
                dot.heightAnchor.constraint(equalToConstant: 24).isActive = true
                dot.accessibilityLabel = "색상 " + hex
                dot.addAction(UIAction { [weak self] _ in self?.settings.color = hex; self?.publish() }, for: .touchUpInside)
                swatches.addArrangedSubview(dot)
            }
            stack.addArrangedSubview(swatches)
            let well = UIColorWell(); well.selectedColor = settings.uiColor; well.supportsAlpha = false; well.accessibilityLabel = "다른 색상"
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 44).isActive = true
            well.addAction(UIAction { [weak self, weak well] _ in guard let self, let color = well?.selectedColor else { return }; self.settings.color = color.hexString; self.publish() }, for: .valueChanged)
            // A small color well sits beside the width controls, instead of a permanent toolbar row.
            let row = UIStackView(); row.alignment = .center; row.spacing = 8
            row.addArrangedSubview(well); row.addArrangedSubview(slider(value: settings.width, min: 0.1, max: 40, unit: "px") { [weak self] in self?.settings.width = $0; self?.publish() })
            stack.addArrangedSubview(row)
            stack.addArrangedSubview(slider(value: settings.opacity * 100, min: 5, max: 100, unit: "%") { [weak self] in self?.settings.opacity = $0 / 100; self?.publish() })
            let recentTitle = UILabel(); recentTitle.text = "최근 색상"; recentTitle.font = .systemFont(ofSize: 11); recentTitle.textColor = .secondaryLabel; stack.addArrangedSubview(recentTitle)
            let recent = UIStackView(); recent.spacing = 0; recent.distribution = .fillEqually
            for hex in UserDefaults.standard.stringArray(forKey: "inkdrive.recent-colors") ?? ["#202020", "#2455D6", "#DB3249", "#FFFFFF"] {
                let dot = InkColorButton(type: .custom); dot.backgroundColor = UIColor(hex: hex); dot.heightAnchor.constraint(equalToConstant: 18).isActive = true; dot.accessibilityLabel = "최근 색상 " + hex
                dot.addAction(UIAction { [weak self] _ in self?.settings.color = hex; self?.publish() }, for: .touchUpInside); recent.addArrangedSubview(dot)
            }
            stack.addArrangedSubview(recent)
        } else if tool == .eraser {
            stack.addArrangedSubview(slider(value: settings.eraserWidth, min: 4, max: 80, unit: "px") { [weak self] in self?.settings.eraserWidth = $0; self?.publish() })
            stack.addArrangedSubview(toggle("부분 지우기", settings.partialEraser) { [weak self] in self?.settings.partialEraser = $0; self?.publish() })
            stack.addArrangedSubview(toggle("펜으로 복귀", settings.returnToPen) { [weak self] in self?.settings.returnToPen = $0; self?.publish() })
        }
        if tool == .marker { stack.addArrangedSubview(toggle("직선 형광펜", settings.markerStraight) { [weak self] in self?.settings.markerStraight = $0; self?.publish() }) }
        let saved = UIButton(type: .system); saved.setTitle("+  즐겨찾기", for: .normal); saved.titleLabel?.font = .systemFont(ofSize: 12); saved.layer.borderWidth = 0.5; saved.layer.borderColor = UIColor(hex: "#E8C65A").cgColor; saved.heightAnchor.constraint(equalToConstant: 36).isActive = true
        saved.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            var values = UserDefaults.standard.array(forKey: "inkdrive.tool-presets.v2") as? [Data] ?? []
            if let value = try? JSONEncoder().encode(ToolPreset(tool: self.tool, settings: self.settings)) { values.append(value); UserDefaults.standard.set(Array(values.suffix(12)), forKey: "inkdrive.tool-presets.v2") }
            self.changed(self.settings)
        }, for: .touchUpInside); stack.addArrangedSubview(saved)
        let more = InkIcons.button("sliders-horizontal", label: "추가 도구 설정")
        more.addAction(UIAction { [weak self] _ in guard let self else { return }; let action = self.advanced; self.dismiss(animated: true, completion: action) }, for: .touchUpInside)
        stack.addArrangedSubview(more)
    }
    private func publish() {
        var colors = UserDefaults.standard.stringArray(forKey: "inkdrive.recent-colors") ?? []
        colors.removeAll { $0 == settings.color }; colors.insert(settings.color, at: 0)
        UserDefaults.standard.set(Array(colors.prefix(12)), forKey: "inkdrive.recent-colors")
        changed(settings)
    }
    private func slider(value: Double, min: Float, max: Float, unit: String, update: @escaping (Double) -> Void) -> UIView {
        let stack = UIStackView(); stack.spacing = 4; stack.alignment = .center
        let slider = UISlider(); slider.minimumValue = min; slider.maximumValue = max; slider.value = Float(value); slider.tintColor = UIColor(hex: "#E8C65A")
        slider.accessibilityLabel = unit == "px" ? "굵기 px" : "불투명도 %"
        let number = UILabel(); number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); number.textColor = UIColor(white: 0.85, alpha: 1)
        number.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let format: (Double) -> String = { String(format: unit == "px" ? "%.1f px" : "%.0f %%", $0) }
        number.text = format(value)
        slider.addAction(UIAction { [weak slider, weak number] _ in guard let slider else { return }; let value = Double(slider.value); number?.text = format(value); update(value) }, for: .valueChanged)
        stack.addArrangedSubview(slider); stack.addArrangedSubview(number)
        for delta: Float in [-1, 1] {
            let button = InkIcons.button(delta < 0 ? "minus" : "plus", label: (unit == "px" ? "굵기" : "불투명도") + (delta < 0 ? " 줄이기" : " 늘리기"), compact: true)
            button.addAction(UIAction { [weak slider, weak number] _ in
                guard let slider else { return }; let step: Float = unit == "px" ? (min >= 4 ? 1 : 0.1) : 5
                slider.value = Swift.max(min, Swift.min(max, slider.value + delta * step))
                let value = Double(slider.value); number?.text = format(value); update(value)
            }, for: .touchUpInside); stack.addArrangedSubview(button)
        }
        stack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return stack
    }
    private func toggle(_ title: String, _ value: Bool, update: @escaping (Bool) -> Void) -> UIView {
        let row = UIStackView(); row.alignment = .center
        let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 13); row.addArrangedSubview(label)
        let control = UISwitch(); control.isOn = value; control.onTintColor = UIColor(hex: "#E8C65A")
        control.addAction(UIAction { [weak control] _ in update(control?.isOn ?? false) }, for: .valueChanged)
        row.addArrangedSubview(control); return row
    }
}
