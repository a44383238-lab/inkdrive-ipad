import UIKit

@MainActor final class SelectionPopoverController: UIViewController {
    let selection: StrokeInteractionView
    let width: Double
    init(selection: StrokeInteractionView, width: Double) {
        self.selection = selection; self.width = width; super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover; preferredContentSize = CGSize(width: 356, height: 116)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .white
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10)])
        let colors = UIStackView(); colors.distribution = .equalSpacing; colors.alignment = .center
        for hex in ["#D44B59", "#22344B", "#3869D4", "#429A80", "#D4A340", "#9670C3"] {
            let dot = InkColorButton(type: .custom); dot.backgroundColor = UIColor(hex: hex); dot.layer.cornerRadius = 13
            dot.widthAnchor.constraint(equalToConstant: 26).isActive = true; dot.heightAnchor.constraint(equalToConstant: 26).isActive = true; dot.accessibilityLabel = "선택한 필기 색상 " + hex
            dot.addAction(UIAction { [weak self] _ in self?.selection.recolor(UIColor(hex: hex)) }, for: .touchUpInside); colors.addArrangedSubview(dot)
        }
        let close = InkIcons.button("x", label: "선택 메뉴 닫기"); close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside); colors.addArrangedSubview(close); stack.addArrangedSubview(colors)
        let actions = UIStackView(); actions.spacing = 3; actions.distribution = .equalSpacing
        func item(_ icon: String, _ label: String, _ action: @escaping () -> Void) {
            let button = InkIcons.button(icon, label: label); button.addAction(UIAction { _ in action() }, for: .touchUpInside); actions.addArrangedSubview(button)
        }
        item("copy", "복사") { [weak self] in self?.selection.copySelection() }
        item("scissors", "잘라내기") { [weak self] in self?.selection.copySelection(); self?.selection.deleteSelection(); self?.dismiss(animated: true) }
        item("clipboard-paste", "붙여넣기") { [weak self] in self?.selection.paste(); self?.dismiss(animated: true) }
        item("rotate-ccw", "선택한 필기 회전") { [weak self] in self?.selection.rotateSelection(-.pi / 12) }
        item("sliders-horizontal", "현재 펜 굵기 적용") { [weak self] in self?.selection.rewidth(self?.width ?? 3) }
        item("trash-2", "선택한 필기 삭제") { [weak self] in self?.selection.deleteSelection(); self?.dismiss(animated: true) }
        stack.addArrangedSubview(actions)
    }
}
