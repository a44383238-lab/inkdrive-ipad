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
    private var lastCommit: Data
    private var toolActive = false
    private var openedGroup = false
    private var closeGroupWork: DispatchWorkItem?
    init(record: NotebookPage, editor: EditorViewController) {
        self.record = record; self.editor = editor; lastCommit = record.drawing.dataRepresentation()
        super.init(frame: .zero)
        isOpaque = false; backgroundColor = .clear
        canvas.drawing = record.drawing; canvas.delegate = self; canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawingPolicy = .pencilOnly; canvas.isScrollEnabled = false
        canvas.drawingGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        canvas.drawingGestureRecognizer.isEnabled = true
        addSubview(canvas); addSubview(interaction)
        interaction.overlay = self
        applyTool()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews(); canvas.frame = bounds; interaction.frame = bounds
    }
    func applyTool() {
        guard let editor else { return }
        let tool = editor.tool
        canvas.tool = editor.settings.nativeTool(tool)
        let customMarker = tool == .marker && editor.settings.markerStraight
        let customEraser = tool == .eraser
        let native = [.pen, .pencil, .marker, .eraser].contains(tool) && !customMarker && !customEraser
        canvas.isUserInteractionEnabled = native
        interaction.isUserInteractionEnabled = !native
        if tool != .lasso { interaction.clearSelection() }
    }
    func refresh() {
        guard !toolActive else { return }
        let data = record.drawing.dataRepresentation()
        guard data != lastCommit else { return }
        synchronizing = true; canvas.drawing = record.drawing; lastCommit = data; synchronizing = false
        interaction.clearSelection()
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !synchronizing else { return }
        // Keep serialization, undo snapshots and PDF invalidation off the live stroke path.
        guard !toolActive else { return }
        beginGroup(); commitDrawing(); scheduleGroupEnd()
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        endGroup(); toolActive = true; editor?.session.beginInkInput(record.id); beginGroup()
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        toolActive = false; editor?.session.endInkInput(record.id); commitDrawing(); scheduleGroupEnd()
        if editor?.tool == .eraser, editor?.settings.returnToPen == true { editor?.setTool(.pen) }
    }
    func commit() {
        toolActive = false; editor?.session.endInkInput(record.id); commitDrawing(); endGroup()
    }
    private func commitDrawing() {
        let data = canvas.drawing.dataRepresentation()
        guard data != lastCommit else { return }
        lastCommit = data
        editor?.session.changeDrawing(pageID: record.id, to: canvas.drawing, alreadyCompared: true)
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
