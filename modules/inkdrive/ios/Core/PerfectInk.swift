import UIKit
import PencilKit

/// FountainPen + an outline mask is the archive carrier for app-owned solid ink.
/// PKCanvasView never renders these carriers; screen, PDF and portable export fill the same outline.
enum PerfectInk {
    static func owns(_ stroke: PKStroke) -> Bool { stroke.ink.inkType == .fountainPen && stroke.mask != nil }
    static func samples(_ stroke: PKStroke) -> [InkSample] {
        stroke.path.map { InkSample(point: $0.location, pressure: $0.force, time: $0.timeOffset) }
    }
    static func make(_ samples: [InkSample], width: CGFloat, color: UIColor, date: Date = Date()) -> PKStroke? {
        guard !samples.isEmpty, width.isFinite, width > 0, samples.count <= 50_000 else { return nil }
        let base = samples[0].time
        let controls = samples.map {
            PKStrokePoint(location: $0.point, timeOffset: max(0, $0.time - base), size: CGSize(width: width, height: width), opacity: 1,
                          force: min(1, max(0, $0.pressure)), azimuth: 0, altitude: .pi / 2)
        }
        let outline = PerfectFreehand.path(samples, size: width)
        guard !outline.isEmpty else { return nil }
        return PKStroke(ink: PKInk(.fountainPen, color: color.withAlphaComponent(1)),
                        path: PKStrokePath(controlPoints: controls, creationDate: date), mask: UIBezierPath(cgPath: outline))
    }
    static func outline(_ stroke: PKStroke) -> CGPath {
        if owns(stroke), let mask = stroke.mask { return mask.cgPath }
        let points = Array(stroke.path.interpolatedPoints(by: .distance(0.5)))
        let shape = VectorInkPainter.outline(points)
        if let mask = stroke.mask { return shape.intersection(mask.cgPath) }
        return shape
    }
    static func bounds(_ stroke: PKStroke) -> CGRect {
        guard owns(stroke) else { return stroke.renderBounds }
        return outline(stroke).boundingBoxOfPath.applying(stroke.transform)
    }
    static func rewidth(_ stroke: PKStroke, width: CGFloat) -> PKStroke {
        let samples = samples(stroke), oldWidth = stroke.path.first?.size.width ?? width
        guard let made = make(samples, width: width, color: stroke.ink.color, date: stroke.path.creationDate) else { return stroke }
        let original = PerfectFreehand.path(samples, size: oldWidth)
        let erased = original.subtracting(outline(stroke))
        let newOutline = erased.isEmpty ? outline(made) : outline(made).subtracting(erased)
        return PKStroke(ink: made.ink, path: made.path, transform: stroke.transform, mask: UIBezierPath(cgPath: newOutline))
    }
    static func commands(_ path: CGPath, map: @escaping (CGPoint) -> CGPoint = { $0 }) -> [[Double]] {
        var result: [[Double]] = []
        path.applyWithBlock { pointer in
            let e = pointer.pointee
            let tag: Int, count: Int
            switch e.type {
            case .moveToPoint: tag = 0; count = 1
            case .addLineToPoint: tag = 1; count = 1
            case .addQuadCurveToPoint: tag = 2; count = 2
            case .addCurveToPoint: tag = 3; count = 3
            case .closeSubpath: tag = 4; count = 0
            @unknown default: return
            }
            var command = [Double(tag)]
            for i in 0..<count { let p = map(e.points[i]); command += [Double(p.x), Double(p.y)] }
            result.append(command)
        }
        return result
    }
}
