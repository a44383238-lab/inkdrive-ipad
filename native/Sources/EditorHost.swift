import SwiftUI

struct EditorHost: UIViewControllerRepresentable {
    let store: NativeLibraryStore
    let document: OpenDocument
    func makeUIViewController(context: Context) -> LoadingEditorController { LoadingEditorController(store: store, document: document) }
    func updateUIViewController(_ uiViewController: LoadingEditorController, context: Context) {}
}

@MainActor final class LoadingEditorController: UIViewController {
    private let store: NativeLibraryStore
    private let document: OpenDocument
    private var started = false
    init(store: NativeLibraryStore, document: OpenDocument) { self.store = store; self.document = document; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = UIColor(hex: "#F8F9FC")
        let spinner = UIActivityIndicatorView(style: .large); spinner.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(spinner)
        NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)]); spinner.startAnimating()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); guard !started else { return }; started = true
        Task {
            do {
                let session: EditorSession
                if let url = document.externalURL { session = try await EditorSession.open(url) }
                else { session = try await store.repository.open(document.path) }
                let editor = EditorViewController(session: session)
                if document.externalURL == nil { configure(editor) }
                editor.didClose = { [weak self, weak editor] in
                    guard let self else { return }
                    if self.document.externalURL == nil {
                        do { try self.store.repository.refreshLessonSources(pdf: editor?.documentPath ?? self.document.path) }
                        catch { self.store.message = error.localizedDescription }
                    }
                    self.store.document = nil; self.store.refresh()
                }
                present(editor, animated: false)
            } catch {
                let alert = UIAlertController(title: "문서", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "서재", style: .cancel) { _ in self.store.document = nil }); present(alert, animated: true)
            }
        }
    }
    private func configure(_ editor: EditorViewController) {
        let repo = store.repository
        let key = "inkdrive.document-tabs." + CoordinatedStore.digest(Data((store.rootName ?? "InkDrive").utf8))
        let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
        editor.documentPath = document.path; editor.documentPaths = Array(([document.path] + previous.filter { $0 != document.path }).prefix(8))
        UserDefaults.standard.set(editor.documentPaths, forKey: key)
        editor.documentsChanged = { UserDefaults.standard.set($0, forKey: key) }
        editor.listDocuments = { try repo.pdfPaths() }
        editor.openDocument = { [weak editor] next in
            if let path = editor?.documentPath { try repo.refreshLessonSources(pdf: path) }
            return try await repo.open(next)
        }
        editor.canRecord = true
        editor.recordingAction = { [weak editor] in
            guard let editor else { throw InkError.unavailable }
            let lesson = try repo.quickLesson(pdf: editor.documentPath, date: NativeLibraryStore.today())
            try await RecordingService.shared.start(lesson: lesson, repository: repo)
        }
        editor.recordingsAction = { [weak self, weak editor] in
            guard let self, let editor else { return }
            do { try self.store.showRecordings(editor.documentPath, from: editor) } catch { editor.showError(error) }
        }
    }
}
