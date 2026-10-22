import UIKit
import PencilKit

enum InkEraser {
    static func erase(_ drawing: PKDrawing, from: CGPoint, to: CGPoint, width: CGFloat, partial: Bool, target: String) -> PKDrawing {
        let radius = max(2, width / 2)
        let trace = CGMutablePath(); trace.move(to: from); trace.addLine(to: to)
        let brush = from == to ? CGPath(ellipseIn: CGRect(x: to.x - radius, y: to.y - radius, width: radius * 2, height: radius * 2), transform: nil) : trace.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            let matches = target == "all" || (target == "marker" ? stroke.ink.inkType == .marker : stroke.ink.inkType != .marker)
            guard matches, PerfectInk.bounds(stroke).intersects(brush.boundingBoxOfPath) else { return stroke }
            let points = Array(stroke.path.interpolatedPoints(by: .distance(max(0.5, radius / 3))))
            guard !points.isEmpty else { return stroke }
            var transform = stroke.transform
            guard let pageOutline = PerfectInk.outline(stroke).copy(using: &transform) else { return stroke }
            let localMask = stroke.mask?.cgPath
            let visible: CGPath
            if let localMask, let pageMask = localMask.copy(using: &transform) { visible = pageOutline.intersection(pageMask) }
            else { visible = pageOutline }
            guard visible.intersects(brush) else { return stroke }
            guard partial else { return nil }
            var inverse = stroke.transform.inverted()
            guard let localBrush = brush.copy(using: &inverse) else { return stroke }
            let mask = localMask ?? VectorInkPainter.outline(points)
            let remaining = mask.subtracting(localBrush)
            guard !remaining.isEmpty else { return nil }
            return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: UIBezierPath(cgPath: remaining))
        }
        return PKDrawing(strokes: strokes)
    }
}
