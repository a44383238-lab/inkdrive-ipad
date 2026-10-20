import UIKit

@MainActor enum InkIcons {
    static func image(_ name: String) -> UIImage? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main.url(forResource: "InkDriveIcons", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? Bundle.main
        #endif
        return UIImage(named: name, in: bundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
    }
    static func button(_ icon: String, label: String) -> UIButton {
        let item = UIButton(type: .system)
        item.setImage(image(icon), for: .normal)
        item.tintColor = UIColor(hex: "#34465D")
        item.accessibilityLabel = label
        item.layer.cornerRadius = 12
        item.heightAnchor.constraint(equalToConstant: 44).isActive = true
        item.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return item
    }
}
