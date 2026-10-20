import UIKit
import PencilKit
import PDFKit

final class PencilCanvas: PKCanvasView {
    override var undoManager: UndoManager? { nil }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if event?.allTouches?.contains(where: { $0.type != .pencil }) == true { return nil }
        return super.hitTest(point, with: event)
    }
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
        canvas.drawingPolicy = .pencilOnly; canvas.isScrollEnabled = false
        canvas.panGestureRecognizer.isEnabled = false
        canvas.pinchGestureRecognizer?.isEnabled = false
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
        let customEraser = tool == .eraser && editor.settings.eraserTarget != "all"
        let native = [.pen, .pencil, .marker, .eraser].contains(tool) && !customMarker && !customEraser
        canvas.isUserInteractionEnabled = native
        interaction.isUserInteractionEnabled = !native && tool != .hand
        if tool != .lasso { interaction.clearSelection() }
    }
    func refresh() {
        let data = record.drawing.dataRepresentation()
        guard data != lastCommit else { return }
        synchronizing = true; canvas.drawing = record.drawing; lastCommit = data; synchronizing = false
        interaction.clearSelection()
    }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !synchronizing else { return }
        // Estimated pressure updates can arrive after DidEndUsingTool. Every callback persists.
        beginGroup(); commitDrawing()
        if !toolActive { scheduleGroupEnd() }
    }
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        toolActive = true; closeGroupWork?.cancel(); beginGroup()
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        toolActive = false; commitDrawing(); scheduleGroupEnd()
        if editor?.tool == .eraser, editor?.settings.returnToPen == true { editor?.setTool(.pen) }
    }
    func commit() {
        commitDrawing(); endGroup()
    }
    private func commitDrawing() {
        let data = canvas.drawing.dataRepresentation()
        guard data != lastCommit else { return }
        lastCommit = data
        editor?.session.changeDrawing(pageID: record.id, to: canvas.drawing)
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
