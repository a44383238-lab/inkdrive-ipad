import UIKit
import PencilKit
import PDFKit

@MainActor final class StrokeInteractionView: UIView {
    weak var overlay: PageOverlay?
    private var points: [CGPoint] = []
    private(set) var selected = Set<Int>()
    private var moving = false
    private var selectionBounds: CGRect = .null
    var selectedBounds: CGRect { selectionBounds }
    private var resizeCorner: CGPoint?
    private var resizeAnchor: CGPoint?
    private let outline = CAShapeLayer()
    private let eraserCircle = CAShapeLayer()
    private var erasing = false
    private var endPoint: CGPoint = .zero
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear
        outline.strokeColor = UIColor.systemBlue.cgColor; outline.fillColor = UIColor.clear.cgColor
        outline.lineDashPattern = [5, 4]; outline.lineWidth = 1.5; layer.addSublayer(outline)
        eraserCircle.fillColor = UIColor(white: 0.15, alpha: 0.14).cgColor
        eraserCircle.strokeColor = UIColor(white: 0.35, alpha: 0.65).cgColor
        eraserCircle.lineWidth = 1; layer.addSublayer(eraserCircle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func clearSelection() { selected.removeAll(); selectionBounds = .null; outline.path = nil }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }
        let point = touch.location(in: self); points = [point]; endPoint = point
        resizeCorner = nil; resizeAnchor = nil
        if let overlay, overlay.editor?.tool == .eraser {
            erasing = true; overlay.canvasViewDidBeginUsingTool(overlay.canvas)
            updateEraser(from: point, to: point); return
        }
        if !selected.isEmpty, !selectionBounds.isNull, overlay?.editor?.tool == .lasso {
            let corners = [CGPoint(x: selectionBounds.minX, y: selectionBounds.minY), CGPoint(x: selectionBounds.maxX, y: selectionBounds.minY), CGPoint(x: selectionBounds.maxX, y: selectionBounds.maxY), CGPoint(x: selectionBounds.minX, y: selectionBounds.maxY)]
            if let corner = corners.first(where: { hypot(point.x - $0.x, point.y - $0.y) < 18 }) {
                resizeCorner = corner; resizeAnchor = CGPoint(x: corner.x == selectionBounds.minX ? selectionBounds.maxX : selectionBounds.minX, y: corner.y == selectionBounds.minY ? selectionBounds.maxY : selectionBounds.minY)
                moving = false; return
            }
        }
        moving = !selected.isEmpty && selectionBounds.insetBy(dx: -12, dy: -12).contains(point)
        if !moving { clearSelection() }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }), let first = points.first else { return }
        if erasing { let next = touch.location(in: self); updateEraser(from: endPoint, to: next); endPoint = next; return }
        endPoint = touch.location(in: self); points.append(endPoint)
        if let anchor = resizeAnchor { drawBounds(CGRect(x: min(anchor.x, endPoint.x), y: min(anchor.y, endPoint.y), width: abs(endPoint.x - anchor.x), height: abs(endPoint.y - anchor.y))); return }
        let path = UIBezierPath()
        if moving { path.append(UIBezierPath(rect: selectionBounds.offsetBy(dx: endPoint.x - first.x, dy: endPoint.y - first.y))) }
        else if overlay?.editor?.tool == .lasso { path.move(to: first); points.dropFirst().forEach { path.addLine(to: $0) } }
        else { path.move(to: first); path.addLine(to: endPoint) }
        outline.path = path.cgPath
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.contains(where: { $0.type == .pencil }) else { return }
        finishErasing(); points = []; resizeCorner = nil; resizeAnchor = nil; updateSelectionBounds()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }), let overlay, let editor = overlay.editor, let first = points.first else { return }
        if erasing { updateEraser(from: endPoint, to: touch.location(in: self)); finishErasing(); return }
        endPoint = touch.location(in: self)
        switch editor.tool {
        case .marker:
            let controls = [first, endPoint].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: editor.settings.width, height: editor.settings.width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            let stroke = PKStroke(ink: PKInk(.marker, color: editor.settings.uiColor), path: PKStrokePath(controlPoints: controls, creationDate: Date()))
            editor.session.changeDrawing(pageID: overlay.record.id, to: PKDrawing(strokes: overlay.record.drawing.strokes + [stroke]))
            outline.path = nil
        case .eraser: break
        case .lasso:
            if let anchor = resizeAnchor, let corner = resizeCorner {
                let x = abs(corner.x - anchor.x) > 0.1 ? (endPoint.x - anchor.x) / (corner.x - anchor.x) : 1
                let y = abs(corner.y - anchor.y) > 0.1 ? (endPoint.y - anchor.y) / (corner.y - anchor.y) : 1
                let transform = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                    .concatenating(CGAffineTransform(scaleX: min(5, max(0.1, x)), y: min(5, max(0.1, y))))
                    .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
                transformSelected(transform)
            } else if moving {
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
        default: break
        }
        points = []; resizeCorner = nil; resizeAnchor = nil
    }
    private func updateEraser(from: CGPoint, to: CGPoint) {
        guard let overlay, let editor = overlay.editor else { return }
        let width = CGFloat(editor.settings.eraserWidth)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        eraserCircle.path = CGPath(ellipseIn: CGRect(x: to.x - width / 2, y: to.y - width / 2, width: width, height: width), transform: nil)
        CATransaction.commit()
        overlay.canvas.drawing = InkEraser.erase(overlay.canvas.drawing, from: from, to: to, width: width, partial: editor.settings.partialEraser, target: editor.settings.eraserTarget)
    }
    private func finishErasing() {
        guard erasing, let overlay else { return }; erasing = false
        eraserCircle.path = nil; points = []
        overlay.canvasViewDidEndUsingTool(overlay.canvas); overlay.commit()
    }
    private func updateSelectionBounds() {
        guard let drawing = overlay?.record.drawing else { return }
        selectionBounds = selected.filter { drawing.strokes.indices.contains($0) }.reduce(CGRect.null) { $0.union(drawing.strokes[$1].renderBounds) }
        drawBounds(selectionBounds)
    }
    private func drawBounds(_ rect: CGRect) {
        guard !rect.isNull else { outline.path = nil; return }
        let path = UIBezierPath(rect: rect)
        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] {
            path.append(UIBezierPath(ovalIn: CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8)))
        }; outline.path = path.cgPath
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
    func rotateSelection(_ angle: CGFloat) {
        guard angle.isFinite, !selectionBounds.isNull else { return }
        let center = CGPoint(x: selectionBounds.midX, y: selectionBounds.midY)
        transformSelected(CGAffineTransform(translationX: -center.x, y: -center.y).concatenating(CGAffineTransform(rotationAngle: angle)).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
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
