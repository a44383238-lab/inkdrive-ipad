import UIKit
import PencilKit
import PDFKit

final class PencilCanvas: PKCanvasView {
    override var undoManager: UndoManager? { nil }
}

@MainActor final class PageOverlay: UIView, PKCanvasViewDelegate {
    let canvas = PencilCanvas()
    let interaction = StrokeInteractionView()
    let record: NotebookPage
    weak var editor: EditorViewController?
    private var synchronizing = false
    private var lastNativeData: Data
    private var nativeChanged = false
    private var customChanged = false
    private var publishing = false
    private var toolActive = false
    private var openedGroup = false
    private var closeGroupWork: DispatchWorkItem?
    private var workingDrawing: PKDrawing
    private let perfectSurface = UIView()
    private var perfectLayers: [CAShapeLayer] = []
    var drawing: PKDrawing {
        // Native tools only see legacy strokes; app-owned outline carriers are never rasterized by PencilKit.
        let native = canvas.drawing.strokes
        var index = 0, merged: [PKStroke] = []
        for stroke in workingDrawing.strokes {
            if PerfectInk.owns(stroke) { merged.append(stroke) }
            else if index < native.count { merged.append(native[index]); index += 1 }
        }
        merged.append(contentsOf: native.dropFirst(index))
        return PKDrawing(strokes: merged)
    }
    init(record: NotebookPage, editor: EditorViewController) {
        self.record = record; self.editor = editor; workingDrawing = record.drawing
        lastNativeData = PKDrawing(strokes: record.drawing.strokes.filter { !PerfectInk.owns($0) }).dataRepresentation()
        super.init(frame: .zero)
        isOpaque = false; backgroundColor = .clear; clipsToBounds = true
        canvas.drawing = PKDrawing(strokes: record.drawing.strokes.filter { !PerfectInk.owns($0) }); canvas.delegate = self; canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .pencilOnly; canvas.isScrollEnabled = false
        canvas.drawingGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvas.drawingGestureRecognizer.isEnabled = true
        perfectSurface.isUserInteractionEnabled = false; perfectSurface.backgroundColor = .clear; perfectSurface.isOpaque = false
        addSubview(canvas); addSubview(perfectSurface); addSubview(interaction)
        interaction.overlay = self
        renderPerfectInk()
        applyTool()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews(); canvas.frame = bounds; perfectSurface.frame = bounds; interaction.frame = bounds
    }
    func applyTool() {
        guard let editor else { return }
        let tool = editor.tool
        canvas.tool = editor.settings.nativeTool(tool)
        let customMarker = tool == .marker && editor.settings.markerStraight
        let customEraser = tool == .eraser
        let native = [.pencil, .marker].contains(tool) && !customMarker && !customEraser
        canvas.isUserInteractionEnabled = native
        interaction.isUserInteractionEnabled = !native
        if tool != .lasso { interaction.clearSelection() }
    }
    func refresh() {
        guard !toolActive, !publishing else { return }
        setDrawing(record.drawing); customChanged = false
        interaction.clearSelection()
    }
    func setDrawing(_ drawing: PKDrawing, preservingNative: Bool = false) {
        synchronizing = true; workingDrawing = drawing
        if !preservingNative {
            canvas.drawing = PKDrawing(strokes: drawing.strokes.filter { !PerfectInk.owns($0) })
            lastNativeData = canvas.drawing.dataRepresentation(); nativeChanged = false
        }
        customChanged = true
        renderPerfectInk(); synchronizing = false
    }
    private func renderPerfectInk() {
        let strokes = workingDrawing.strokes.filter(PerfectInk.owns)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while perfectLayers.count > strokes.count { perfectLayers.removeLast().removeFromSuperlayer() }
        while perfectLayers.count < strokes.count {
            let layer = CAShapeLayer(); layer.fillRule = .nonZero; layer.contentsScale = UIScreen.main.scale
            perfectSurface.layer.addSublayer(layer); perfectLayers.append(layer)
        }
        for (layer, stroke) in zip(perfectLayers, strokes) {
            layer.fillRule = stroke.mask?.usesEvenOddFillRule == true ? .evenOdd : .nonZero
            layer.path = PerfectInk.outline(stroke); layer.fillColor = stroke.ink.color.withAlphaComponent(1).cgColor
            position(layer, path: PerfectInk.outline(stroke), transform: stroke.transform)
        }
        CATransaction.commit()
        updateInkScale()
    }
    private func position(_ layer: CAShapeLayer, path: CGPath, transform: CGAffineTransform) {
        let box = path.boundingBoxOfPath
        guard !box.isNull, !box.isEmpty else { return }
        // A real local bound is required for layer snapshots and clipping. Keep it stroke-sized,
        // rather than allocating a page-sized backing surface for every stroke.
        layer.bounds = box; layer.anchorPoint = .zero; layer.position = box.origin.applying(transform)
        layer.setAffineTransform(CGAffineTransform(a: transform.a,b: transform.b,c: transform.c,d: transform.d,tx: 0,ty: 0))
    }
    func updateInkScale() {
        let scale = UIScreen.main.scale * max(1, editor?.pdfView.scaleFactor ?? 1)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        perfectSurface.contentScaleFactor = scale
        for layer in perfectLayers { layer.contentsScale = scale; layer.shouldRasterize = false }
        CATransaction.commit()
    }
    func previewSelection(_ selection: Set<Int>, by transform: CGAffineTransform?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        var layerIndex = 0
        for (index, stroke) in workingDrawing.strokes.enumerated() where PerfectInk.owns(stroke) {
            if layerIndex < perfectLayers.count {
                let delta = selection.contains(index) ? (transform ?? .identity) : .identity
                position(perfectLayers[layerIndex], path: PerfectInk.outline(stroke), transform: stroke.transform.concatenating(delta))
            }
            layerIndex += 1
        }
        CATransaction.commit()
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !synchronizing else { return }
        nativeChanged = true
        // Keep serialization, undo snapshots and PDF invalidation off the live stroke path.
        guard !toolActive else { return }
        beginGroup(); commitDrawing(); scheduleGroupEnd()
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        endGroup(); toolActive = true; editor?.session.beginInkInput(record.id); beginGroup()
        editor?.setInkInputActive(true)
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        toolActive = false; editor?.session.endInkInput(record.id); commitDrawing(); scheduleGroupEnd()
        editor?.setInkInputActive(false)
        if editor?.tool == .eraser, editor?.settings.returnToPen == true { editor?.setTool(.pen) }
    }
    func commit() {
        interaction.finishPen(presentSelection: false)
        toolActive = false; editor?.session.endInkInput(record.id); commitDrawing(); endGroup()
        editor?.setInkInputActive(false)
    }
    private func commitDrawing() {
        guard nativeChanged || customChanged else { return }
        if nativeChanged {
            let data = canvas.drawing.dataRepresentation(); nativeChanged = false
            if data == lastNativeData && !customChanged { return }
            lastNativeData = data
        }
        let current = drawing
        workingDrawing = current; customChanged = false
        publishing = true; defer { publishing = false }
        editor?.session.changeDrawing(pageID: record.id, to: current, alreadyCompared: true)
    }
    private func beginGroup() {
        guard !openedGroup, let history = editor?.session.history else { return }
        history.beginUndoGrouping(); openedGroup = true
    }
    private func scheduleGroupEnd() {
        closeGroupWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.endGroup() }
        closeGroupWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }
    private func endGroup() {
        closeGroupWork?.cancel(); closeGroupWork = nil
        guard openedGroup else { return }
        openedGroup = false
        if let history = editor?.session.history, history.groupingLevel > 0 { history.endUndoGrouping() }
    }
}

@MainActor final class OverlayProvider: NSObject, PDFPageOverlayViewProvider {
    weak var editor: EditorViewController?
    var overlays: [UUID: PageOverlay] = [:]
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let editor, let record = editor.session.model.record(for: page) else { return nil }
        if let existing = overlays[record.id] { return existing }
        let overlay = PageOverlay(record: record, editor: editor)
        overlays[record.id] = overlay
        return overlay
    }
    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let overlay = overlayView as? PageOverlay else { return }
        overlay.commit(); overlays.removeValue(forKey: overlay.record.id)
    }
    func commitAll() { Array(overlays.values).forEach { $0.commit() } }
    func refreshAll() { Array(overlays.values).forEach { $0.refresh() } }
    func applyTool() { Array(overlays.values).forEach { $0.applyTool() } }
}
