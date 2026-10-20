import UIKit
import PencilKit
import PDFKit

@MainActor final class StrokeInteractionView: UIView {
    weak var overlay: PageOverlay?
    private var points: [CGPoint] = []
    private(set) var selected = Set<Int>()
    private var moving = false
    private var selectionBounds: CGRect = .null
    private let outline = CAShapeLayer()
    private var endPoint: CGPoint = .zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear
        outline.strokeColor = UIColor.systemBlue.cgColor; outline.fillColor = UIColor.clear.cgColor
        outline.lineDashPattern = [5, 4]; outline.lineWidth = 1.5; layer.addSublayer(outline)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if event?.allTouches?.contains(where: { $0.type != .pencil }) == true { return nil }
        return super.hitTest(point, with: event)
    }
    func clearSelection() { selected.removeAll(); selectionBounds = .null; outline.path = nil }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        let point = touch.location(in: self); points = [point]; endPoint = point
        moving = !selected.isEmpty && selectionBounds.insetBy(dx: -12, dy: -12).contains(point)
        if !moving { clearSelection() }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let first = points.first else { return }
        endPoint = touch.location(in: self); points.append(endPoint)
        let path = UIBezierPath()
        if moving { path.append(UIBezierPath(rect: selectionBounds.offsetBy(dx: endPoint.x - first.x, dy: endPoint.y - first.y))) }
        else if overlay?.editor?.tool == .lasso { path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) } }
        else { path.move(to: first); path.addLine(to: endPoint) }
        outline.path = path.cgPath
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { points = []; outline.path = nil }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let overlay, let editor = overlay.editor, let first = points.first else { return }
        if let touch = touches.first { endPoint = touch.location(in: self) }
        switch editor.tool {
        case .marker:
            let controls = [first, endPoint].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: editor.settings.width, height: editor.settings.width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            let stroke = PKStroke(ink: PKInk(.marker, color: editor.settings.uiColor), path: PKStrokePath(controlPoints: controls, creationDate: Date()))
            editor.session.changeDrawing(pageID: overlay.record.id, to: PKDrawing(strokes: overlay.record.drawing.strokes + [stroke]))
            outline.path = nil
        case .eraser:
            let target = editor.settings.eraserTarget
            let radius = max(4, editor.settings.eraserWidth / 2)
            let trace = points + [endPoint]
            let strokes = overlay.record.drawing.strokes.filter { stroke in
                let matches = target == "marker" ? stroke.ink.inkType == .marker : stroke.ink.inkType != .marker
                guard matches else { return true }
                return !stroke.path.contains { point in
                    let transformed = point.location.applying(stroke.transform)
                    return trace.contains { hypot($0.x - transformed.x, $0.y - transformed.y) <= radius }
                }
            }
            editor.session.changeDrawing(pageID: overlay.record.id, to: PKDrawing(strokes: strokes)); outline.path = nil
            if editor.settings.returnToPen { editor.setTool(.pen) }
        case .lasso:
            if moving {
                let transform = CGAffineTransform(translationX: endPoint.x - first.x, y: endPoint.y - first.y)
                transformSelected(transform)
            } else {
                let polygon = UIBezierPath(); polygon.move(to: first); points.dropFirst().forEach { polygon.addLine(to: $0) }; polygon.close()
                selected = Set(overlay.record.drawing.strokes.enumerated().compactMap { i, stroke in
                    stroke.path.contains(where: { polygon.contains($0.location.applying(stroke.transform)) }) ? i : nil
                })
                updateSelectionBounds()
            }
            if !selected.isEmpty { editor.selectionMenu(self) }
        case .text:
            editor.textGesture(record: overlay.record, from: first, to: endPoint)
            outline.path = nil
        case .line, .rectangle, .ellipse:
            editor.addShape(record: overlay.record, from: first, to: endPoint)
            outline.path = nil
        default: break
        }
        points = []
    }
    private func updateSelectionBounds() {
        guard let drawing = overlay?.record.drawing else { return }
        selectionBounds = selected.filter { drawing.strokes.indices.contains($0) }.reduce(CGRect.null) { $0.union(drawing.strokes[$1].renderBounds) }
        outline.path = selectionBounds.isNull ? nil : UIBezierPath(rect: selectionBounds).cgPath
    }
    func transformSelected(_ transform: CGAffineTransform) {
        mutate { stroke in PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform.concatenating(transform), mask: stroke.mask) }
    }
    func scaleSelection(_ factor: CGFloat) {
        guard factor.isFinite, (0.1...5).contains(factor), !selectionBounds.isNull else { return }
        let x = selectionBounds.minX, y = selectionBounds.minY
        let transform = CGAffineTransform(translationX: -x, y: -y).concatenating(CGAffineTransform(scaleX: factor, y: factor)).concatenating(CGAffineTransform(translationX: x, y: y))
        transformSelected(transform)
    }
    func recolor(_ color: UIColor) {
        mutate { PKStroke(ink: PKInk($0.ink.inkType, color: color), path: $0.path, transform: $0.transform, mask: $0.mask) }
    }
    func rewidth(_ width: CGFloat) {
        mutate { stroke in
            let controls = stroke.path.map { point in
                PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: CGSize(width: width, height: width), opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude)
            }
            return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: controls, creationDate: stroke.path.creationDate), transform: stroke.transform, mask: stroke.mask)
        }
    }
    private func mutate(_ work: (PKStroke) -> PKStroke) {
        guard let overlay, let editor = overlay.editor else { return }
        let chosen = selected
        let strokes = overlay.record.drawing.strokes.enumerated().map { chosen.contains($0.offset) ? work($0.element) : $0.element }
        editor.session.changeDrawing(pageID: overlay.record.id, to: PKDrawing(strokes: strokes))
        selected = chosen; updateSelectionBounds()
    }
    func copySelection() {
        guard let drawing = overlay?.record.drawing else { return }
        let strokes = drawing.strokes.enumerated().filter { selected.contains($0.offset) }.map(\.element)
        UIPasteboard.general.setData(PKDrawing(strokes: strokes).dataRepresentation(), forPasteboardType: "app.inkdrive.drawing")
    }
    func deleteSelection() {
        guard let overlay, let editor = overlay.editor else { return }
        let strokes = overlay.record.drawing.strokes.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
        editor.session.changeDrawing(pageID: overlay.record.id, to: PKDrawing(strokes: strokes)); clearSelection()
    }
    func paste() {
        guard let overlay, let editor = overlay.editor,
              let bytes = UIPasteboard.general.data(forPasteboardType: "app.inkdrive.drawing"),
              let drawing = try? PKDrawing(data: bytes) else { return }
        let offset = drawing.transformed(using: CGAffineTransform(translationX: 20, y: 20))
        editor.session.changeDrawing(pageID: overlay.record.id, to: PKDrawing(strokes: overlay.record.drawing.strokes + offset.strokes))
    }
}
