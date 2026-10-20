import UIKit
import PDFKit

@MainActor final class PageListController: UITableViewController, UISearchResultsUpdating {
    unowned let editor: EditorViewController
    private let modes = UISegmentedControl(items: ["페이지", "목차", "북마크", "검색"])
    private let search = UISearchController(searchResultsController: nil)
    private var found: [PDFSelection] = []
    private var outline: [(title: String, page: PDFPage)] = []
    private var bookmarks: Set<String> = []
    private var searchTimer: Timer?
    private var foundToken: NSObjectProtocol?
    private var bookmarkKey: String { "inkdrive.bookmarks." + CoordinatedStore.digest(Data(editor.session.store.url.absoluteString.utf8)) }
    private var bookmarkedPages: [NotebookPage] { editor.session.model.pages.filter { bookmarks.contains($0.id.uuidString) } }
    init(editor: EditorViewController) { self.editor = editor; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "페이지"
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: InkIcons.image("arrow-left"), style: .plain, target: self, action: #selector(done))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "필기로"
        let plus = UIBarButtonItem(image: InkIcons.image("plus"), style: .plain, target: self, action: #selector(add)); plus.accessibilityLabel = "페이지 추가"
        let jump = UIBarButtonItem(image: InkIcons.image("search"), style: .plain, target: self, action: #selector(jumpToPage)); jump.accessibilityLabel = "페이지 번호로 이동"
        navigationItem.rightBarButtonItems = [plus, editButtonItem, jump]
        bookmarks = Set(UserDefaults.standard.stringArray(forKey: bookmarkKey) ?? [])
        if let root = editor.session.model.pdf.outlineRoot { readOutline(root, depth: 0) }
        modes.selectedSegmentIndex = 0; modes.addTarget(self, action: #selector(changeMode), for: .valueChanged)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 58)); modes.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(modes)
        NSLayoutConstraint.activate([modes.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16), modes.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16), modes.centerYAnchor.constraint(equalTo: header.centerYAnchor), modes.heightAnchor.constraint(equalToConstant: 44)])
        tableView.tableHeaderView = header; tableView.allowsSelectionDuringEditing = true; tableView.rowHeight = 96
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.searchBar.placeholder = "문서 검색"; definesPresentationContext = true
        foundToken = NotificationCenter.default.addObserver(forName: .PDFDocumentDidFindMatch, object: editor.session.model.pdf, queue: .main) { [weak self] note in
            guard let selection = note.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else { return }
            Task { @MainActor in guard let self, self.modes.selectedSegmentIndex == 3 else { return }; self.found.append(selection); self.tableView.reloadData() }
        }
    }
    deinit { searchTimer?.invalidate(); if let foundToken { NotificationCenter.default.removeObserver(foundToken) } }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); searchTimer?.invalidate(); editor.session.model.pdf.cancelFindString() }
    private func readOutline(_ item: PDFOutline, depth: Int) {
        if let page = item.destination?.page ?? (item.action as? PDFActionGoTo)?.destination.page {
            outline.append((String(repeating: "  ", count: min(depth, 5)) + (item.label ?? "목차"), page))
        }
        for index in 0..<item.numberOfChildren { if let child = item.child(at: index) { readOutline(child, depth: depth + 1) } }
    }
    @objc private func changeMode() {
        setEditing(false, animated: true); editButtonItem.isEnabled = modes.selectedSegmentIndex == 0
        searchTimer?.invalidate(); editor.session.model.pdf.cancelFindString(); found = []
        navigationItem.searchController = modes.selectedSegmentIndex == 3 ? search : nil
        tableView.reloadData()
    }
    func updateSearchResults(for searchController: UISearchController) {
        searchTimer?.invalidate(); editor.session.model.pdf.cancelFindString(); found = []; tableView.reloadData()
        let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return }
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.editor.session.model.pdf.beginFindString(query, withOptions: [.caseInsensitive]) }
        }
    }
    @objc private func jumpToPage() {
        let alert = UIAlertController(title: "페이지 이동", message: "1–\(editor.session.model.pages.count)", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad; $0.placeholder = "페이지 번호" }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "이동", style: .default) { _ in
            guard let number = Int(alert.textFields?.first?.text ?? ""), self.editor.session.model.pages.indices.contains(number - 1) else { return }
            let page = self.editor.session.model.pages[number - 1].page
            self.dismiss(animated: true) { self.editor.pdfView.go(to: page) }
        }); present(alert, animated: true)
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
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch modes.selectedSegmentIndex { case 1: return outline.count; case 2: return bookmarkedPages.count; case 3: return found.count; default: return editor.session.model.pages.count }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if modes.selectedSegmentIndex == 1 {
            let item = outline[indexPath.row]; cell.textLabel?.text = item.title; cell.textLabel?.numberOfLines = 2
            cell.detailTextLabel?.text = "\(editor.session.model.pdf.index(for: item.page) + 1) 페이지"; return cell
        }
        if modes.selectedSegmentIndex == 3 {
            let item = found[indexPath.row]; cell.textLabel?.text = item.string; cell.textLabel?.numberOfLines = 2
            if let page = item.pages.first { cell.detailTextLabel?.text = "\(editor.session.model.pdf.index(for: page) + 1) 페이지" }; return cell
        }
        let record = modes.selectedSegmentIndex == 2 ? bookmarkedPages[indexPath.row] : editor.session.model.pages[indexPath.row]
        cell.textLabel?.text = "\(editor.session.model.pdf.index(for: record.page) + 1) 페이지"
        cell.accessoryType = bookmarks.contains(record.id.uuidString) ? .checkmark : .none
        cell.detailTextLabel?.text = nil
        cell.imageView?.image = record.page.thumbnail(of: CGSize(width: 60, height: 80), for: .cropBox)
        return cell
    }
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { modes.selectedSegmentIndex == 0 }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { modes.selectedSegmentIndex == 0 }
    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard modes.selectedSegmentIndex == 0 else { return nil }
        let id = editor.session.model.pages[indexPath.row].id.uuidString
        let action = UIContextualAction(style: .normal, title: bookmarks.contains(id) ? "북마크 해제" : "북마크") { _, _, done in
            if self.bookmarks.contains(id) { self.bookmarks.remove(id) } else { self.bookmarks.insert(id) }
            UserDefaults.standard.set(Array(self.bookmarks), forKey: self.bookmarkKey); self.editor.session.preservePageIdentities(); tableView.reloadData(); done(true)
        }; action.image = InkIcons.image("bookmark"); action.backgroundColor = UIColor(hex: "#3665BF")
        return UISwipeActionsConfiguration(actions: [action])
    }
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
        if modes.selectedSegmentIndex == 3 {
            let selection = found[indexPath.row]
            search.isActive = false
            dismiss(animated: true) { self.editor.pdfView.setCurrentSelection(selection, animate: true); self.editor.pdfView.go(to: selection) }; return
        }
        let page: PDFPage
        if modes.selectedSegmentIndex == 1 { page = outline[indexPath.row].page }
        else if modes.selectedSegmentIndex == 2 { page = bookmarkedPages[indexPath.row].page }
        else { page = editor.session.model.pages[indexPath.row].page }
        dismiss(animated: true) { self.editor.pdfView.go(to: page) }
    }
}
