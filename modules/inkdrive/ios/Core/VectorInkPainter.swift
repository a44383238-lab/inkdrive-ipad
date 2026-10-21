import UIKit
import PencilKit

/// PDF appearance uses paths. The lossless PKDrawing remains embedded for editing.
/// Pencil grain is an approximation; point sizes, transforms and eraser clips are retained.
enum VectorInkPainter {
    static func draw(_ drawing: PKDrawing, in context: CGContext) {
        for stroke in drawing.strokes {
            context.saveGState()
            context.concatenate(stroke.transform)
            if let mask = stroke.mask {
                context.addPath(mask.cgPath)
                context.clip(using: mask.usesEvenOddFillRule ? .evenOdd : .winding)
            }
            let points = Array(stroke.path.interpolatedPoints(by: .distance(0.5)))
            guard !points.isEmpty, points.allSatisfy({ p in
                p.location.x.isFinite && p.location.y.isFinite && p.size.width.isFinite && p.size.height.isFinite && p.size.width > 0 && p.size.height > 0 && p.opacity.isFinite
            }) else { context.restoreGState(); continue }
            let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let uniform = points.allSatisfy { abs($0.opacity - points[0].opacity) < 0.0001 }
            context.setFillColor(color.cgColor)
            if uniform {
                context.setAlpha(points[0].opacity)
                context.addPath(outline(points)); context.fillPath()
            } else {
                // Variable opacity stays in the portable samples; individual capsules approximate the nib.
                for i in points.indices {
                    context.setAlpha(points[i].opacity)
                    context.addPath(outline(i == 0 ? [points[i]] : [points[i - 1], points[i]])); context.fillPath()
                }
            }
            context.restoreGState()
        }
    }
    private static func outline(_ points: [PKStrokePoint]) -> CGPath {
        let path = CGMutablePath()
        for p in points {
            path.addEllipse(in: CGRect(x: p.location.x - p.size.width / 2, y: p.location.y - p.size.height / 2, width: p.size.width, height: p.size.height))
        }
        for i in points.indices.dropFirst() {
            let a = points[i - 1], b = points[i]
            let dx = b.location.x - a.location.x, dy = b.location.y - a.location.y, length = hypot(dx, dy)
            guard length > 0.000001 else { continue }
            let nx = -dy / length, ny = dx / length
            func radius(_ p: PKStrokePoint) -> CGFloat { hypot(p.size.width * nx / 2, p.size.height * ny / 2) }
            let ar = radius(a), br = radius(b)
            path.move(to: CGPoint(x: a.location.x + nx * ar, y: a.location.y + ny * ar))
            path.addLine(to: CGPoint(x: a.location.x - nx * ar, y: a.location.y - ny * ar))
            path.addLine(to: CGPoint(x: b.location.x - nx * br, y: b.location.y - ny * br))
            path.addLine(to: CGPoint(x: b.location.x + nx * br, y: b.location.y + ny * br)); path.closeSubpath()
        }
        return path
    }
}
