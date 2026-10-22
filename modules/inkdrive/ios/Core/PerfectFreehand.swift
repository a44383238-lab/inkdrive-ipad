// Swift adaptation of perfect-freehand 1.2.3, Copyright (c) 2021 Stephen Ruiz Ltd.
// MIT: see ThirdParty/perfect-freehand-LICENSE.txt.
// The native pen uses real pressure, round caps, no artificial taper, no velocity pressure.
import Foundation
import CoreGraphics

struct InkSample {
    var point: CGPoint
    var pressure: CGFloat
    var time: TimeInterval
}

enum PerfectFreehand {
    struct SamplePoint {
        var point: CGPoint
        var pressure: CGFloat
        var vector: CGPoint
        var distance: CGFloat
        var runningLength: CGFloat
    }
    static let thinning: CGFloat = 0.6
    private static let pi = CGFloat.pi + 0.0001
    static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func mul(_ a: CGPoint, _ n: CGFloat) -> CGPoint { CGPoint(x: a.x * n, y: a.y * n) }
    static func per(_ a: CGPoint) -> CGPoint { CGPoint(x: a.y, y: -a.x) }
    static func dot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.x + a.y * b.y }
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    static func unit(_ a: CGPoint) -> CGPoint { let n = hypot(a.x, a.y); return n > 0 ? mul(a, 1 / n) : .zero }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { add(a, mul(sub(b, a), t)) }
    static func rotate(_ a: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let p = sub(a, center), s = sin(angle), c = cos(angle)
        return add(center, CGPoint(x: p.x * c - p.y * s, y: p.x * s + p.y * c))
    }
    static func radius(size: CGFloat, pressure: CGFloat) -> CGFloat {
        max(0.01, size * (0.5 - thinning * (0.5 - min(1, max(0, pressure)))))
    }
    static func points(_ input: [InkSample], size: CGFloat, complete: Bool) -> [SamplePoint] {
        guard !input.isEmpty else { return [] }
        var samples = input
        if samples.count == 2 {
            let a = samples[0], b = samples[1]
            // Preserve real endpoint pressure instead of replacing interpolated pressure with 0.5.
            samples = [a] + (1...4).map { i in
                let t = CGFloat(i) / 4
                return InkSample(point: lerp(a.point, b.point, t), pressure: a.pressure + (b.pressure - a.pressure) * t, time: a.time + (b.time - a.time) * Double(t))
            }
        }
        if samples.count == 1 {
            var b = samples[0]; b.point = add(b.point, CGPoint(x: 1, y: 1)); samples.append(b)
        }
        let first = samples[0]
        var result = [SamplePoint(point: first.point, pressure: first.pressure, vector: CGPoint(x: 1, y: 1), distance: 0, runningLength: 0)]
        var previous = result[0], reached = false, running: CGFloat = 0
        for i in 1..<samples.count {
            // Streamline is deliberately zero: do not drag the pen tip behind the input.
            let point = samples[i].point
            if point == previous.point { continue }
            let d = distance(point, previous.point); running += d
            if i < samples.count - 1 && !reached {
                if running < size { continue }; reached = true
            }
            previous = SamplePoint(point: point, pressure: samples[i].pressure, vector: unit(sub(previous.point, point)), distance: d, runningLength: running)
            result.append(previous)
        }
        result[0].vector = result.count > 1 ? result[1].vector : .zero
        return result
    }
    static func outline(_ input: [InkSample], size: CGFloat, complete: Bool = true) -> [CGPoint] {
        guard size.isFinite, size > 0 else { return [] }
        let points = points(input, size: size, complete: complete)
        guard let first = points.first, let last = points.last else { return [] }
        let minDistance = pow(size * 0.35, 2)
        var left: [CGPoint] = [], right: [CGPoint] = []
        var previousVector = first.vector, previousLeft = first.point, previousRight = first.point
        var radius = self.radius(size: size, pressure: last.pressure), firstRadius: CGFloat?
        var wasSharp = false
        for i in points.indices {
            let p = points[i], isLast = i == points.count - 1
            if !isLast && last.runningLength - p.runningLength < 3 { continue }
            radius = self.radius(size: size, pressure: p.pressure)
            if firstRadius == nil { firstRadius = radius }
            let next = isLast ? p.vector : points[i + 1].vector
            let nextDot = isLast ? 1 : dot(p.vector, next)
            let sharp = dot(p.vector, previousVector) < 0 && !wasSharp
            let nextSharp = nextDot < 0
            if sharp || nextSharp {
                let offset = mul(per(previousVector), radius)
                var t: CGFloat = 0
                while t <= 1 {
                    let l = rotate(sub(p.point, offset), around: p.point, by: pi * t)
                    let r = rotate(add(p.point, offset), around: p.point, by: -pi * t)
                    left.append(l); right.append(r); previousLeft = l; previousRight = r
                    t += 1 / 13
                }
                if nextSharp { wasSharp = true }
                continue
            }
            wasSharp = false
            if isLast {
                let offset = mul(per(p.vector), radius)
                left.append(sub(p.point, offset)); right.append(add(p.point, offset)); continue
            }
            let offset = mul(per(lerp(next, p.vector, nextDot)), radius)
            let l = sub(p.point, offset), r = add(p.point, offset)
            if i <= 1 || pow(distance(previousLeft, l), 2) > minDistance { left.append(l); previousLeft = l }
            if i <= 1 || pow(distance(previousRight, r), 2) > minDistance { right.append(r); previousRight = r }
            previousVector = p.vector
        }
        if points.count == 1 {
            let offset = unit(per(CGPoint(x: -1, y: -1)))
            let start = sub(first.point, mul(offset, firstRadius ?? radius))
            var circle: [CGPoint] = [], t: CGFloat = 1 / 13
            while t <= 1 { circle.append(rotate(start, around: first.point, by: pi * 2 * t)); t += 1 / 13 }
            return circle
        }
        guard let rightStart = right.first else { return [] }
        var startCap: [CGPoint] = [], endCap: [CGPoint] = []
        var t: CGFloat = 1 / 13
        while t <= 1 { startCap.append(rotate(rightStart, around: first.point, by: pi * t)); t += 1 / 13 }
        let start = add(last.point, mul(per(mul(last.vector, -1)), radius))
        t = 1 / 29
        while t < 1 { endCap.append(rotate(start, around: last.point, by: pi * 3 * t)); t += 1 / 29 }
        return left + endCap + Array(right.reversed()) + startCap
    }
    static func path(_ input: [InkSample], size: CGFloat, complete: Bool = true) -> CGPath {
        path(from: outline(input, size: size, complete: complete))
    }
    static func path(from outline: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = outline.first else { return path }
        path.move(to: first)
        // Keep the upstream polygon exact. Dense Pencil samples and rounded joins provide smooth edges.
        for point in outline.dropFirst() { path.addLine(to: point) }; path.closeSubpath()
        return path
    }
}

/// Only confirmed, monotonic samples enter a saved stroke. Predictions never enter this buffer.
struct InkInputBuffer {
    private(set) var samples: [InkSample] = []
    mutating func append(_ sample: InkSample) -> Bool {
        guard sample.point.x.isFinite, sample.point.y.isFinite, sample.pressure.isFinite, sample.time.isFinite,
              samples.count < 50_000 else { return false }
        if let last = samples.last, sample.time <= last.time { return false }
        var value = sample; value.pressure = min(1, max(0, value.pressure))
        samples.append(value); return true
    }
}
