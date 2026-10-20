import UIKit
import PencilKit

enum EditorTool: String, CaseIterable {
    case pen, pencil, marker, eraser, lasso, text
    var label: String { switch self {
    case .pen: return "펜"
    case .pencil: return "연필"
    case .marker: return "형광펜"
    case .eraser: return "지우개"
    case .lasso: return "올가미"
    case .text: return "텍스트"
    } }
    var icon: String { switch self {
    case .pen: return "pen-tool"
    case .pencil: return "pencil"
    case .marker: return "highlighter"
    case .eraser: return "eraser"
    case .lasso: return "lasso-select"
    case .text: return "type"
    } }
}
struct ToolSettings: Codable {
    var color = "#2455D6"
    var width: Double = 3
    var opacity: Double = 1
    var eraserWidth: Double = 20
    var partialEraser = false
    var returnToPen = false
    var markerStraight = false
    var eraserTarget = "all"
    var fillShape = false
    var fontSize: Double = 18
    var font = "system"
    var alignment = 0
    var uiColor: UIColor { UIColor(hex: color).withAlphaComponent(opacity) }
    var uiFont: UIFont {
        switch font {
        case "serif": return UIFont(name: "Georgia", size: fontSize) ?? .systemFont(ofSize: fontSize)
        case "mono": return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        default: return .systemFont(ofSize: fontSize)
        }
    }
    func nativeTool(_ tool: EditorTool) -> PKTool {
        if tool == .eraser {
            return partialEraser ? PKEraserTool(.bitmap, width: eraserWidth) : PKEraserTool(.vector)
        }
        let type: PKInk.InkType = tool == .pencil ? .pencil : tool == .marker ? .marker : .pen
        return PKInkingTool(type, color: uiColor, width: width)
    }
}
extension UIColor {
    convenience init(hex: String) {
        let number = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x2455D6
        self.init(red: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255, blue: CGFloat(number & 255) / 255, alpha: 1)
    }
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
