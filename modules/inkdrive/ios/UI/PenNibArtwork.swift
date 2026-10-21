import UIKit

/// Original vector nib drawings, rendered at the display scale; no borrowed app assets.
@MainActor enum PenNibArtwork {
    static func image(tool: EditorTool, color: UIColor, width: Double) -> UIImage? {
        guard [.pen, .pencil, .marker].contains(tool) else { return InkIcons.image(tool.icon) }
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 34)).image { context in
            let c = context.cgContext
            c.setFillColor(color.cgColor)
            let body = UIBezierPath()
            if tool == .marker {
                body.move(to: CGPoint(x: 9, y: 2)); body.addLine(to: CGPoint(x: 23, y: 2)); body.addLine(to: CGPoint(x: 21, y: 17)); body.addLine(to: CGPoint(x: 11, y: 20))
            } else {
                body.move(to: CGPoint(x: 9, y: 1)); body.addLine(to: CGPoint(x: 23, y: 1)); body.addLine(to: CGPoint(x: 21, y: 10)); body.addLine(to: CGPoint(x: 16, y: 23)); body.addLine(to: CGPoint(x: 11, y: 10))
            }
            body.close(); body.fill()
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor); c.setLineWidth(0.7); body.stroke()
            c.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
            c.move(to: CGPoint(x: 16, y: 10)); c.addLine(to: CGPoint(x: 16, y: 22)); c.strokePath()
            let label = String(format: width < 10 ? "%.1f" : "%.0f", width)
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular), .foregroundColor: UIColor(white: 0.8, alpha: 1)]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: CGPoint(x: (32 - size.width) / 2, y: 24), withAttributes: attributes)
        }.withRenderingMode(.alwaysOriginal)
    }
}
