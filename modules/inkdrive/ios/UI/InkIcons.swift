import UIKit

final class InkColorButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: min(0, (bounds.width - 44) / 2), dy: min(0, (bounds.height - 44) / 2)).contains(point)
    }
}

@MainActor enum InkIcons {
    static func image(_ name: String) -> UIImage? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main.url(forResource: "InkDriveIcons", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.main
        #endif
        return UIImage(named: name, in: bundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
    }
    static func button(_ icon: String, label: String, compact: Bool = false) -> UIButton {
        let item = InkColorButton(type: .system)
        item.setImage(image(icon), for: .normal)
        item.tintColor = UIColor(white: 0.88, alpha: 1)
        item.accessibilityLabel = label
        item.layer.cornerRadius = compact ? 3 : 10
        item.heightAnchor.constraint(equalToConstant: compact ? 36 : 44).isActive = true
        item.widthAnchor.constraint(equalToConstant: compact ? 36 : 44).isActive = true
        return item
    }
}
