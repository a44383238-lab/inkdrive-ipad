import Foundation
import CoreGraphics

enum InkShapeKind: String { case line, circle, rectangle }
struct InkShape {
    let kind: InkShapeKind
    let points: [CGPoint]
    var samples: [InkSample] { points.enumerated().map { InkSample(point: $0.element, pressure: 0.5, time: Double($0.offset) / 240) } }
}
enum InkShapeRecognizer {
    static func recognize(_ samples: [InkSample], scale: CGFloat) -> InkShape? {
        let points = samples.map(\.point)
        guard let first = points.first, let last = points.last, points.count >= 3 else { return nil }
        let bounds = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
        let length = zip(points, points.dropFirst()).reduce(CGFloat(0)) { $0 + PerfectFreehand.distance($1.0, $1.1) }
        let chord = PerfectFreehand.distance(first, last), diagonal = hypot(bounds.width, bounds.height)
        let safeScale = max(0.1, scale), minimum = 18 / safeScale
        guard diagonal >= minimum, length >= minimum else { return nil }
        if chord >= minimum, length / chord < 1.18 {
            let direction = PerfectFreehand.sub(last, first)
            let error = points.map { p -> CGFloat in
                let v = PerfectFreehand.sub(p, first)
                return abs(v.x * direction.y - v.y * direction.x) / chord
            }.max() ?? .infinity
            if error < max(3 / safeScale, chord * 0.045) {
                return InkShape(kind: .line, points: (0...12).map { PerfectFreehand.lerp(first, last, CGFloat($0) / 12) })
            }
        }
        guard chord <= max(10 / safeScale, diagonal * 0.22), min(bounds.width, bounds.height) >= minimum * 0.6,
              points.count >= 8 else { return nil }
        let cx = bounds.midX, cy = bounds.midY, rx = bounds.width / 2, ry = bounds.height / 2
        let radial = points.map { abs(hypot(($0.x - cx) / rx, ($0.y - cy) / ry) - 1) }
        let ellipseError = radial.reduce(0) { $0 + $1 * $1 } / CGFloat(radial.count)
        // Require a complete, single revolution rather than turning a scribble into a circle.
        let perimeter = CGFloat.pi * (3 * (rx + ry) - sqrt((3 * rx + ry) * (rx + 3 * ry)))
        if ellipseError < 0.012, length / perimeter > 0.72, length / perimeter < 1.35,
           max(rx, ry) / min(rx, ry) < 1.45 {
            let radius = (rx + ry) / 2
            return InkShape(kind: .circle, points: (0...96).map { i in
                let angle = CGFloat(i) / 96 * .pi * 2
                return CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
            })
        }
        // Fit a rotated rectangle, then require all four corners and the perimeter to be visited.
        let center = CGPoint(x: cx, y: cy)
        var best: (angle: CGFloat, bounds: CGRect, area: CGFloat)?
        for i in 0..<60 {
            let angle = CGFloat(i) * .pi / 120
            let rotated = points.map { PerfectFreehand.rotate($0, around: center, by: -angle) }
            let box = rotated.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: CGSize(width: 0.001, height: 0.001))) }
            let area = box.width * box.height
            if best == nil || area < best!.area { best = (angle, box, area) }
        }
        guard let fit = best, min(fit.bounds.width, fit.bounds.height) >= minimum * 0.6 else { return nil }
        let rotated = points.map { PerfectFreehand.rotate($0, around: center, by: -fit.angle) }, b = fit.bounds
        let edgeError = rotated.map { min(abs($0.x - b.minX), abs($0.x - b.maxX), abs($0.y - b.minY), abs($0.y - b.maxY)) }
        let rms = sqrt(edgeError.reduce(0) { $0 + $1 * $1 } / CGFloat(edgeError.count))
        guard rms < max(2 / safeScale, diagonal * 0.035), length / (2 * (b.width + b.height)) > 0.72,
              length / (2 * (b.width + b.height)) < 1.35 else { return nil }
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
        guard corners.allSatisfy({ corner in (rotated.map { PerfectFreehand.distance($0, corner) }.min() ?? .infinity) < diagonal * 0.13 }) else { return nil }
        var result: [CGPoint] = []
        for i in 0..<4 {
            for j in 0..<16 { result.append(PerfectFreehand.rotate(PerfectFreehand.lerp(corners[i], corners[(i + 1) % 4], CGFloat(j) / 16), around: center, by: fit.angle)) }
        }
        result.append(result[0]); return InkShape(kind: .rectangle, points: result)
    }
}

struct InkHoldGate {
    static let delay: TimeInterval = 1.5
    private(set) var anchor: CGPoint?
    private(set) var lastMovement: TimeInterval = 0
    mutating func update(_ point: CGPoint, at time: TimeInterval, scale: CGFloat) -> Bool {
        if anchor == nil || PerfectFreehand.distance(anchor!, point) > 3 / max(0.1, scale) {
            anchor = point; lastMovement = time; return true
        }
        return false
    }
    func ready(at time: TimeInterval) -> Bool { anchor != nil && time - lastMovement >= Self.delay }
}
