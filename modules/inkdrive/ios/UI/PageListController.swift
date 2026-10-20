import UIKit
import PDFKit

@MainActor final class PageListController: UITableViewController {
    unowned let editor: EditorViewController
    init(editor: EditorViewController) { self.editor = editor; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "페이지"
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: InkIcons.image("arrow-left"), style: .plain, target: self, action: #selector(done))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "필기로"
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: InkIcons.image("plus"), style: .plain, target: self, action: #selector(add))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "페이지 추가"
        tableView.isEditing = true; tableView.allowsSelectionDuringEditing = true; tableView.rowHeight = 96
    }
    @objc private func done() { dismiss(animated: true) }
    @objc private func add() {
        let alert = UIAlertController(title: "새 페이지", message: "마지막에 추가해요.", preferredStyle: .actionSheet)
        for template in PaperTemplate.allCases {
            let label = template == .plain ? "무지" : template == .ruled ? "줄노트" : "모눈"
            alert.addAction(UIAlertAction(title: label, style: .default) { _ in
                do { try self.editor.session.insertPage(at: self.editor.session.model.pages.count, template: template); self.tableView.reloadData() }
                catch { self.editor.showError(error) }
            })
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel)); alert.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(alert, animated: true)
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { editor.session.model.pages.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let record = editor.session.model.pages[indexPath.row]
        cell.textLabel?.text = "\(indexPath.row + 1) 페이지"
        cell.detailTextLabel?.text = record.drawing.strokes.isEmpty ? "필기 없음" : "필기 \(record.drawing.strokes.count)획"
        cell.imageView?.image = record.page.thumbnail(of: CGSize(width: 60, height: 80), for: .cropBox)
        return cell
    }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        do { try editor.session.movePage(from: sourceIndexPath.row, to: destinationIndexPath.row); tableView.reloadData() }
        catch { editor.showError(error); tableView.reloadData() }
    }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let record = editor.session.model.pages[indexPath.row]
        let alert = UIAlertController(title: "\(indexPath.row + 1) 페이지 삭제", message: "필기와 주석도 함께 삭제돼요. 실행 취소로 되돌릴 수 있어요.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { _ in
            do { try self.editor.session.deletePage(id: record.id); self.tableView.reloadData() }
            catch { self.editor.showError(error) }
        }); present(alert, animated: true)
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let page = editor.session.model.pages[indexPath.row].page
        dismiss(animated: true) { self.editor.pdfView.go(to: page) }
    }
}
