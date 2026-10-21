import UIKit
import PDFKit

@MainActor final class PageOverviewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UITableViewDataSource, UITableViewDelegate {
    unowned let editor: EditorViewController
    private let documents = UITableView()
    private let grid: UICollectionView
    private var paths: [String] = []
    init(editor: EditorViewController) {
        self.editor = editor
        let layout = UICollectionViewFlowLayout(); layout.itemSize = CGSize(width: 156, height: 212); layout.minimumInteritemSpacing = 28; layout.minimumLineSpacing = 24; layout.sectionInset = UIEdgeInsets(top: 32, left: 30, bottom: 32, right: 30)
        grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = .dark; view.backgroundColor = UIColor(white: 0.12, alpha: 1); view.tintColor = UIColor(hex: "#F4CA52")
        title = editor.session.store.url.deletingPathExtension().lastPathComponent
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: InkIcons.image("arrow-left"), style: .plain, target: self, action: #selector(done)); navigationItem.leftBarButtonItem?.accessibilityLabel = "필기로"
        navigationItem.rightBarButtonItem?.accessibilityLabel = "페이지 추가"
        let find = UIBarButtonItem(image: InkIcons.image("search"), style: .plain, target: self, action: #selector(searchPages)); find.accessibilityLabel = "목차·북마크·검색"
        let plus = UIBarButtonItem(image: InkIcons.image("plus"), style: .plain, target: self, action: #selector(add)); plus.accessibilityLabel = "페이지 추가"
        navigationItem.rightBarButtonItems = [plus, find]
        paths = (try? editor.listDocuments?()) ?? []
        documents.dataSource = self; documents.delegate = self; documents.rowHeight = 64; documents.backgroundColor = UIColor(white: 0.145, alpha: 1); documents.separatorStyle = .none
        grid.dataSource = self; grid.delegate = self; grid.backgroundColor = .clear; grid.register(PagePreviewCell.self, forCellWithReuseIdentifier: "page")
        documents.translatesAutoresizingMaskIntoConstraints = false; grid.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(documents); view.addSubview(grid)
        NSLayoutConstraint.activate([
            documents.leadingAnchor.constraint(equalTo: view.leadingAnchor), documents.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), documents.bottomAnchor.constraint(equalTo: view.bottomAnchor), documents.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.25),
            grid.leadingAnchor.constraint(equalTo: documents.trailingAnchor), grid.trailingAnchor.constraint(equalTo: view.trailingAnchor), grid.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), grid.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    @objc private func done() { dismiss(animated: true) }
    @objc private func searchPages() {
        let navigator = PageListController(editor: editor)
        navigationController?.pushViewController(navigator, animated: true)
    }
    @objc private func add() {
        let menu = UIAlertController(title: "페이지 추가", message: nil, preferredStyle: .actionSheet)
        let index = editor.pdfView.currentPage.map { editor.session.model.pdf.index(for: $0) + 1 } ?? editor.session.model.pages.count
        for template in PaperTemplate.allCases {
            menu.addAction(UIAlertAction(title: template == .plain ? "무지" : template == .ruled ? "줄노트" : template == .yellowRuled ? "노란 줄노트" : "모눈", style: .default) { _ in
                do { self.editor.provider.commitAll(); try self.editor.session.insertPage(at: index, template: template); self.grid.reloadData() }
                catch { self.editor.showError(error) }
            })
        }
        menu.addAction(UIAlertAction(title: "취소", style: .cancel)); menu.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first; present(menu, animated: true)
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { editor.session.model.pages.count + 1 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "page", for: indexPath) as! PagePreviewCell
        if indexPath.item == editor.session.model.pages.count {
            cell.picture.image = nil; cell.number.text = "+"; cell.picture.layer.borderWidth = 1; cell.picture.layer.borderColor = UIColor(white: 0.3, alpha: 1).cgColor; cell.accessibilityLabel = "페이지 추가"
        } else {
            let page = editor.session.model.pages[indexPath.item].page
            cell.picture.image = NotebookPreview.image(editor.session.model.pages[indexPath.item], size: CGSize(width: 260, height: 340)); cell.number.text = "\(indexPath.item + 1)"
            cell.picture.layer.borderWidth = page === editor.pdfView.currentPage ? 2 : 0; cell.picture.layer.borderColor = UIColor(hex: "#F4CA52").cgColor
            cell.accessibilityLabel = "\(indexPath.item + 1) 페이지"
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < editor.session.model.pages.count else { add(); return }
        let page = editor.session.model.pages[indexPath.item].page
        dismiss(animated: true) { self.editor.pdfView.go(to: page) }
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard editor.session.model.pages.indices.contains(indexPath.item) else { return nil }
        let id = editor.session.model.pages[indexPath.item].id
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [UIAction(title: "앞으로 이동", image: UIImage(systemName: "arrow.left")) { _ in
                guard let current = self.editor.session.model.pages.firstIndex(where: { $0.id == id }), current > 0 else { return }
                do { self.editor.provider.commitAll(); try self.editor.session.movePage(from: current, to: current - 1); self.grid.reloadData() } catch { self.editor.showError(error) }
            }, UIAction(title: "뒤로 이동", image: UIImage(systemName: "arrow.right")) { _ in
                guard let current = self.editor.session.model.pages.firstIndex(where: { $0.id == id }), current + 1 < self.editor.session.model.pages.count else { return }
                do { self.editor.provider.commitAll(); try self.editor.session.movePage(from: current, to: current + 1); self.grid.reloadData() } catch { self.editor.showError(error) }
            }, UIAction(title: "삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                let confirm = UIAlertController(title: "페이지를 삭제할까요?", message: nil, preferredStyle: .alert)
                confirm.addAction(UIAlertAction(title: "취소", style: .cancel))
                confirm.addAction(UIAlertAction(title: "삭제", style: .destructive) { _ in
                    do { self.editor.provider.commitAll(); try self.editor.session.deletePage(id: id); self.grid.reloadData() } catch { self.editor.showError(error) }
                }); self.present(confirm, animated: true)
            }])
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { paths.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil); let path = paths[indexPath.row]
        cell.textLabel?.text = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent; cell.textLabel?.font = .systemFont(ofSize: 12); cell.textLabel?.numberOfLines = 2
        cell.backgroundColor = path == editor.documentPath ? .black : .clear
        cell.imageView?.image = InkIcons.image("file-text"); cell.imageView?.tintColor = .secondaryLabel
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Task { @MainActor in
            await editor.switchToDocument(paths[indexPath.row]); title = editor.session.store.url.deletingPathExtension().lastPathComponent
            grid.reloadData(); documents.reloadData()
        }
    }
}

@MainActor private final class PagePreviewCell: UICollectionViewCell {
    let picture = UIImageView()
    let number = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame); picture.contentMode = .scaleAspectFit; number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); number.textAlignment = .center
        picture.translatesAutoresizingMaskIntoConstraints = false; number.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(picture); contentView.addSubview(number)
        NSLayoutConstraint.activate([picture.topAnchor.constraint(equalTo: contentView.topAnchor), picture.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), picture.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), picture.heightAnchor.constraint(equalToConstant: 178), number.topAnchor.constraint(equalTo: picture.bottomAnchor, constant: 8), number.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)])
        isAccessibilityElement = true; accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
