import UIKit

@MainActor enum InkTheme {
    static let canvas = UIColor(white: 0.12, alpha: 1)
    static let panel = UIColor(white: 0.145, alpha: 1)
    static let row = UIColor(white: 0.20, alpha: 1)
    static let text = UIColor(white: 0.92, alpha: 1)
    static let muted = UIColor(white: 0.64, alpha: 1)
    static let accent = UIColor(hex: "#F4CA52")
    static let danger = UIColor(hex: "#F07780")
    static func navigation(_ controller: UIViewController) {
        controller.overrideUserInterfaceStyle = .dark
        controller.view.tintColor = accent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground(); appearance.backgroundColor = panel
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: text, .font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
        controller.navigationController?.navigationBar.standardAppearance = appearance
        controller.navigationController?.navigationBar.scrollEdgeAppearance = appearance
        controller.navigationController?.navigationBar.compactAppearance = appearance
        controller.navigationController?.navigationBar.tintColor = accent
    }
    static func table(_ table: UITableView) {
        table.backgroundColor = panel; table.separatorColor = row
        table.sectionHeaderTopPadding = 0
    }
}

/// Shared app-owned menus and confirmations; system file/share/permission UI stays native.
@MainActor final class InkPanelController: UIViewController, UIPopoverPresentationControllerDelegate {
    enum Style { case alert, actionSheet }
    private let message: String?
    private let style: Style
    private var actions: [InkPanelAction] = []
    private(set) var textFields: [UITextField]?
    init(title: String?, message: String?, preferredStyle: Style) {
        self.message = message; style = preferredStyle
        super.init(nibName: nil, bundle: nil); self.title = title
        modalPresentationStyle = preferredStyle == .actionSheet ? .popover : .overFullScreen
        modalTransitionStyle = .crossDissolve
        popoverPresentationController?.delegate = self
        popoverPresentationController?.backgroundColor = InkTheme.panel
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func addAction(_ action: InkPanelAction) { actions.append(action) }
    func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        let field = UITextField(); configurationHandler?(field)
        if textFields == nil { textFields = [] }; textFields?.append(field)
    }
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = .dark; view.tintColor = InkTheme.accent
        view.backgroundColor = style == .alert ? UIColor.black.withAlphaComponent(0.5) : InkTheme.panel
        let card = UIView(); card.backgroundColor = InkTheme.panel; card.layer.cornerRadius = 12
        card.layer.borderColor = InkTheme.row.cgColor; card.layer.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(card)
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(scroll)
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        if let title, !title.isEmpty {
            let label = UILabel(); label.text = title; label.textColor = InkTheme.text
            label.font = .systemFont(ofSize: 15, weight: .semibold); label.numberOfLines = 0
            stack.addArrangedSubview(label); stack.setCustomSpacing(16, after: label)
        }
        if let message, !message.isEmpty {
            let label = UILabel(); label.text = message; label.numberOfLines = 0
            label.font = .systemFont(ofSize: 13); label.textColor = InkTheme.muted
            stack.addArrangedSubview(label); stack.setCustomSpacing(16, after: label)
        }
        for field in textFields ?? [] {
            field.backgroundColor = InkTheme.canvas; field.textColor = InkTheme.text
            field.font = .systemFont(ofSize: 14); field.layer.cornerRadius = 6
            let padding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
            field.leftView = padding; field.leftViewMode = .always; field.borderStyle = .none
            field.heightAnchor.constraint(equalToConstant: 44).isActive = true
            field.accessibilityLabel = field.placeholder; stack.addArrangedSubview(field)
        }
        for (index, action) in actions.enumerated() {
            let button = UIButton(type: .system); button.setTitle(action.title, for: .normal)
            button.accessibilityLabel = action.title; button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.contentHorizontalAlignment = .leading
            button.setTitleColor(action.style == .destructive ? InkTheme.danger : action.style == .cancel ? InkTheme.muted : InkTheme.text, for: .normal)
            button.backgroundColor = action.style == .cancel ? .clear : InkTheme.row; button.layer.cornerRadius = 6
            button.configuration = .plain(); button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.actions.indices.contains(index) else { return }; self.view.endEditing(true)
                let action = self.actions[index]; self.actions.removeAll()
                self.dismiss(animated: true) { action.handler?(action) }
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 18), scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        let height = stack.systemLayoutSizeFitting(CGSize(width: 304, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height + 32
        preferredContentSize = CGSize(width: 336, height: min(620, height))
        if style == .alert {
            let center = card.centerYAnchor.constraint(equalTo: view.centerYAnchor); center.priority = .defaultHigh
            let heightConstraint = card.heightAnchor.constraint(equalToConstant: min(620, height)); heightConstraint.priority = .defaultHigh
            NSLayoutConstraint.activate([center, heightConstraint, card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
                card.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
                card.widthAnchor.constraint(equalToConstant: 336), card.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -24),
                card.heightAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.heightAnchor, constant: -24)])
            view.accessibilityViewIsModal = true
        } else {
            NSLayoutConstraint.activate([card.topAnchor.constraint(equalTo: view.topAnchor), card.bottomAnchor.constraint(equalTo: view.bottomAnchor), card.leadingAnchor.constraint(equalTo: view.leadingAnchor), card.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        }
    }
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { actions.removeAll() }
}

@MainActor struct InkPanelAction {
    enum Style { case `default`, cancel, destructive }
    let title: String
    let style: Style
    let handler: ((InkPanelAction) -> Void)?
    init(title: String, style: Style, handler: ((InkPanelAction) -> Void)? = nil) { self.title = title; self.style = style; self.handler = handler }
}
