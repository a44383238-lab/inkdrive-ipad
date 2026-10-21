import UIKit

@MainActor final class DocumentTabsController: UITableViewController, UISearchResultsUpdating {
    private let paths: [String]
    private var filtered: [String]
    private let selected: (String) -> Void
    private let search = UISearchController(searchResultsController: nil)
    init(paths: [String], selected: @escaping (String) -> Void) {
        self.paths = paths; filtered = paths; self.selected = selected; super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); InkTheme.navigation(self); InkTheme.table(tableView); title = "문서"
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: InkIcons.image("arrow-left"), style: .plain, target: self, action: #selector(close))
        navigationItem.leftBarButtonItem?.accessibilityLabel = "필기로"
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false; search.searchBar.placeholder = "검색"
        navigationItem.searchController = search; definesPresentationContext = true; tableView.rowHeight = 64
    }
    @objc private func close() { dismiss(animated: true) }
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        filtered = paths.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }; tableView.reloadData()
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filtered.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let path = filtered[indexPath.row], cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        cell.detailTextLabel?.text = (path as NSString).deletingLastPathComponent
        cell.imageView?.image = InkIcons.image("file-text"); cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let path = filtered[indexPath.row]; search.isActive = false
        dismiss(animated: true) { self.selected(path) }
    }
}
