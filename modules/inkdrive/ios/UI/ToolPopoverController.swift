import UIKit

@MainActor final class ToolPopoverController: UIViewController {
    private let tool: EditorTool
    private var settings: ToolSettings
    private let changed: (ToolSettings) -> Void
    var removeTool: (() -> Void)?
    var advanced: (() -> Void)?
    init(tool: EditorTool, settings: ToolSettings, changed: @escaping (ToolSettings) -> Void) {
        self.tool = tool; self.settings = settings; self.changed = changed
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        preferredContentSize = CGSize(width: 296, height: tool == .marker ? 370 : 320)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .white
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18)])
        let header = UIStackView(); header.alignment = .center
        let title = UILabel(); title.text = tool.label; title.font = .systemFont(ofSize: 16, weight: .semibold); header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        let hide = InkIcons.button("minus", label: "도구막대에서 빼기")
        hide.addAction(UIAction { [weak self] _ in guard let self else { return }; let action = self.removeTool; self.dismiss(animated: true, completion: action) }, for: .touchUpInside)
        header.addArrangedSubview(hide); stack.addArrangedSubview(header)
        if tool != .eraser && tool != .lasso {
            let swatches = UIStackView(); swatches.distribution = .equalSpacing
            for hex in ["#22344B", "#3869D4", "#D44B59", "#429A80", "#D4A340", "#9670C3"] {
                let dot = InkColorButton(type: .custom); dot.backgroundColor = UIColor(hex: hex); dot.layer.cornerRadius = 15
                dot.widthAnchor.constraint(equalToConstant: 30).isActive = true; dot.heightAnchor.constraint(equalToConstant: 30).isActive = true
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
            row.addArrangedSubview(well); row.addArrangedSubview(slider(value: settings.width, min: 0.5, max: 40, unit: "px") { [weak self] in self?.settings.width = $0; self?.publish() })
            stack.addArrangedSubview(row)
            stack.addArrangedSubview(slider(value: settings.opacity * 100, min: 5, max: 100, unit: "%") { [weak self] in self?.settings.opacity = $0 / 100; self?.publish() })
        } else if tool == .eraser {
            stack.addArrangedSubview(slider(value: settings.eraserWidth, min: 4, max: 80, unit: "px") { [weak self] in self?.settings.eraserWidth = $0; self?.publish() })
            stack.addArrangedSubview(toggle("부분 지우기", settings.partialEraser) { [weak self] in self?.settings.partialEraser = $0; self?.publish() })
            stack.addArrangedSubview(toggle("펜으로 복귀", settings.returnToPen) { [weak self] in self?.settings.returnToPen = $0; self?.publish() })
        }
        if tool == .marker { stack.addArrangedSubview(toggle("직선 형광펜", settings.markerStraight) { [weak self] in self?.settings.markerStraight = $0; self?.publish() }) }
        let more = InkIcons.button("sliders-horizontal", label: "추가 도구 설정")
        more.addAction(UIAction { [weak self] _ in guard let self else { return }; let action = self.advanced; self.dismiss(animated: true, completion: action) }, for: .touchUpInside)
        stack.addArrangedSubview(more)
    }
    private func publish() { changed(settings) }
    private func slider(value: Double, min: Float, max: Float, unit: String, update: @escaping (Double) -> Void) -> UIView {
        let stack = UIStackView(); stack.spacing = 10; stack.alignment = .center
        let slider = UISlider(); slider.minimumValue = min; slider.maximumValue = max; slider.value = Float(value); slider.tintColor = UIColor(hex: "#3869D4")
        slider.accessibilityLabel = unit == "px" ? "굵기 px" : "불투명도 %"
        let number = UILabel(); number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); number.textColor = UIColor(hex: "#485B73")
        number.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let format: (Double) -> String = { String(format: unit == "px" ? "%.1f px" : "%.0f %%", $0) }
        number.text = format(value)
        slider.addAction(UIAction { [weak slider, weak number] _ in guard let slider else { return }; let value = Double(slider.value); number?.text = format(value); update(value) }, for: .valueChanged)
        stack.addArrangedSubview(slider); stack.addArrangedSubview(number); stack.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return stack
    }
    private func toggle(_ title: String, _ value: Bool, update: @escaping (Bool) -> Void) -> UIView {
        let row = UIStackView(); row.alignment = .center
        let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 13); row.addArrangedSubview(label)
        let control = UISwitch(); control.isOn = value; control.onTintColor = UIColor(hex: "#3869D4")
        control.addAction(UIAction { [weak control] _ in update(control?.isOn ?? false) }, for: .valueChanged)
        row.addArrangedSubview(control); return row
    }
}
