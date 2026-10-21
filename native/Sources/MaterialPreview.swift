import SwiftUI
import QuickLook
import WebKit

struct MaterialDocument: Identifiable { let id = UUID(); let url: URL; let scope: SecurityScope }
struct MaterialPreview: UIViewControllerRepresentable {
    let document: MaterialDocument
    func makeCoordinator() -> Coordinator { Coordinator(document) }
    func makeUIViewController(context: Context) -> QLPreviewController { let view = QLPreviewController(); view.dataSource = context.coordinator; return view }
    func updateUIViewController(_ view: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let document: MaterialDocument
        init(_ document: MaterialDocument) { self.document = document }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { document.url as NSURL }
    }
}
struct HTMLMaterialView: View {
    let document: MaterialDocument
    let store: NativeLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var browser: WKWebView?
    @State private var error: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            SandboxedHTML(document: document, ready: { browser = $0 })
                .navigationTitle(document.url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "arrow.left") }.accessibilityLabel("서재로") }
                    ToolbarItem(placement: .topBarTrailing) { Button("필기용 고정본") { snapshot() }.disabled(browser == nil || saving) }
                }
                .alert("InkDrive", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("확인", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func snapshot() {
        guard let browser else { return }; saving = true
        guard browser.scrollView.contentSize.height <= 18000 else { saving = false; error = "긴 자료는 페이지를 나눈 고정본이 필요해요."; return }
        let rect = CGRect(origin: .zero, size: CGSize(width: browser.bounds.width, height: min(18000, max(browser.bounds.height, browser.scrollView.contentSize.height))))
        let config = WKPDFConfiguration(); config.rect = rect
        browser.createPDF(configuration: config) { result in
            Task { @MainActor in
                saving = false
                do {
                    let data = try result.get(), scope = try store.repository.access(), filename = CampusHTML.safeName(document.url.deletingPathExtension().lastPathComponent) + "_\(UUID().uuidString.prefix(8)).pdf"
                    let folder = scope.url.appendingPathComponent("Snapshots")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try data.write(to: folder.appendingPathComponent(filename), options: .withoutOverwriting)
                    let adapter = DocumentAdapter(kind: "html-snapshot", originalPath: String(document.url.path.dropFirst(scope.url.path.count + 1)), originalSHA256: try FileHasher.digest(document.url), width: Double(rect.width), height: Double(rect.height))
                    try JSONEncoder().encode(adapter).write(to: folder.appendingPathComponent(filename + ".adapter.json"), options: .atomic)
                    dismiss(); store.refresh()
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
struct SandboxedHTML: UIViewRepresentable {
    let document: MaterialDocument
    let ready: (WKWebView) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(ready) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let browser = WKWebView(frame: .zero, configuration: config); browser.navigationDelegate = context.coordinator
        browser.loadFileURL(document.url, allowingReadAccessTo: document.url.deletingLastPathComponent()); return browser
    }
    func updateUIView(_ browser: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let ready: (WKWebView) -> Void
        init(_ ready: @escaping (WKWebView) -> Void) { self.ready = ready }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready(webView) }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
