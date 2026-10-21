import SwiftUI
import WebKit

struct CampusBrowser: UIViewRepresentable {
    let browser: WKWebView
    func makeUIView(context: Context) -> WKWebView { browser }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
struct CampusPanel: View {
    @ObservedObject var campus: CampusSync
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { campus.check() } label: { Label("지금 확인", systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(campus.running)
                if campus.running { ProgressView() }
                Text(campus.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Menu {
                    Button("PLATO") { campus.webView.load(URLRequest(url: URL(string: "https://plato.pusan.ac.kr/")!)) }
                    Button("학지시 · 시간표") { campus.webView.load(URLRequest(url: URL(string: "https://onestop.pusan.ac.kr/")!)) }
                    Button("로그아웃", role: .destructive) { campus.logout() }
                } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44) }
            }
            CampusBrowser(browser: campus.webView).frame(height: 660).clipShape(RoundedRectangle(cornerRadius: 16))
            if let checked = campus.state.lastChecked { Text(checked, style: .time).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
