import Foundation
import WebKit
import Network
import UIKit
import Combine

enum CampusError: LocalizedError {
    case login, response, file, origin
    var errorDescription: String? {
        switch self {
        case .login: return "학교 로그인을 확인해 주세요."
        case .response: return "학교 응답을 읽지 못했어요. 저장한 자료는 유지돼요."
        case .file: return "자료 형식이나 크기를 확인해야 해요."
        case .origin: return "학교 외부 주소로 인증 정보를 보내지 않았어요."
        }
    }
}
struct CampusCourse: Codable, Identifiable {
    let id: Int; let fullname: String; let shortname: String
    var startdate: Double?; var enddate: Double?
    var identity: (term: String, code: String)? {
        guard let regex = try? NSRegularExpression(pattern: "(20[0-9]{2}-[0-9]{4}),\\s*([A-Za-z0-9]+_[A-Za-z0-9]+)"),
              let match = regex.firstMatch(in: shortname, range: NSRange(shortname.startIndex..., in: shortname)),
              let term = Range(match.range(at: 1), in: shortname), let code = Range(match.range(at: 2), in: shortname) else { return nil }
        return (String(shortname[term]), String(shortname[code]))
    }
}
struct CampusResource: Codable, Identifiable { let id: String; let title: String; let kind: String; let url: String }
struct CampusAttachment: Codable { let sha256: String; let path: String; let checked: Date }
struct CampusState: Codable {
    var courses: [CampusCourse] = []; var resources: [String: [CampusResource]] = [:]
    var attachments: [String: CampusAttachment] = [:]; var lastChecked: Date?
}
enum CampusHTML {
    static func matches(_ pattern: String, _ value: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: value).map { String(value[$0]) } ?? "" }
        }
    }
    static func text(_ html: String) -> String {
        html.replacingOccurrences(of: "(?is)<(?:script|style)\\b[^>]*>.*?</(?:script|style)>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func resources(_ html: String) -> [CampusResource] {
        var seen = Set<String>()
        return matches("<a\\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", html).compactMap { row in
            let href = row[1].replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: href, relativeTo: URL(string: "https://plato.pusan.ac.kr/"))?.absoluteURL,
                  url.host == "plato.pusan.ac.kr", url.scheme == "https",
                  let kind = ["ubfile", "resource", "assign", "url", "folder", "page", "forum"].first(where: { url.path == "/mod/\($0)/view.php" }),
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems?.first(where: { $0.name == "id" })?.value,
                  id.range(of: "^[0-9]+$", options: .regularExpression) != nil, seen.insert(kind + id).inserted else { return nil }
            return CampusResource(id: id, title: String(text(row[2]).prefix(120)), kind: kind, url: url.absoluteString)
        }
    }
    static func pluginFiles(_ html: String) -> [URL] {
        var seen = Set<String>()
        return matches("(?:href|src)=[\"']([^\"']*pluginfile\\.php[^\"']*)[\"']", html).compactMap {
            guard let url = URL(string: $0[1].replacingOccurrences(of: "&amp;", with: "&"), relativeTo: URL(string: "https://plato.pusan.ac.kr/"))?.absoluteURL,
                  url.host == "plato.pusan.ac.kr", url.scheme == "https", seen.insert(url.absoluteString).inserted else { return nil }; return url
        }
    }
    static func safeName(_ value: String) -> String {
        var name = String(value.replacingOccurrences(of: "[<>:\"/\\\\|?*\\p{Cc}]", with: "_", options: .regularExpression).prefix(90)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if (try? FileNames.checked(name)) == nil { name = "자료_" + String(CoordinatedStore.digest(Data(value.utf8)).prefix(10)) }; return name
    }
}

final class CampusRedirects: NSObject, URLSessionTaskDelegate {
    static let hosts: Set<String> = ["plato.pusan.ac.kr", "onestop.pusan.ac.kr", "login.pusan.ac.kr"]
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && Self.hosts.contains(request.url?.host ?? "") ? request : nil)
    }
}

@MainActor final class CampusSync: ObservableObject {
    @Published var running = false
    @Published var status = "학교 로그인 후 확인"
    @Published var state = CampusState()
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let repository: LibraryRepository
    private var timer: Timer?
    private var monitor: NWPathMonitor?
    private var session: URLSession?
    private var scope: SecurityScope?
    private var loadedRoot: String?
    private var lastAttempt = Date.distantPast
    private let device = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    init(repository: LibraryRepository) {
        self.repository = repository
        webView.load(URLRequest(url: URL(string: "https://plato.pusan.ac.kr/")!))
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.checkIfDue() } }
        let watcher = NWPathMonitor(); monitor = watcher
        watcher.pathUpdateHandler = { [weak self] path in if path.status == .satisfied { Task { @MainActor in self?.lastAttempt = .distantPast; self?.checkIfDue() } } }
        watcher.start(queue: DispatchQueue(label: "inkdrive.campus.network"))
    }
    deinit { timer?.invalidate(); monitor?.cancel() }
    func checkIfDue() {
        guard UIApplication.shared.applicationState == .active else { return }
        let interval: Double = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3600 : 1800
        if Date().timeIntervalSince(max(state.lastChecked ?? .distantPast, lastAttempt)) >= interval { check(manual: false) }
    }
    private func stateURL(_ root: URL) -> URL { root.appendingPathComponent(".inkdrive/campus/devices/\(device).json") }
    private func persist() throws {
        guard let root = scope?.url else { throw InkError.unavailable }
        let url = stateURL(root); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
    func check(manual: Bool = true) {
        guard !running else { return }; running = true; lastAttempt = Date()
        Task {
            defer { running = false; session?.invalidateAndCancel(); session = nil; scope = nil }
            do {
                scope = try repository.access()
                let root = scope!.url
                if loadedRoot != root.path {
                    state = (try? JSONDecoder().decode(CampusState.self, from: Data(contentsOf: stateURL(root)))) ?? CampusState(); loadedRoot = root.path
                }
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 180
                config.httpCookieStorage = HTTPCookieStorage.shared
                for cookie in config.httpCookieStorage?.cookies ?? [] { config.httpCookieStorage?.deleteCookie(cookie) }
                for cookie in cookies { config.httpCookieStorage?.setCookie(cookie) }
                session = URLSession(configuration: config, delegate: CampusRedirects(), delegateQueue: nil)
                status = "과목 확인 중"
                let home = try await html("https://plato.pusan.ac.kr/")
                guard let key = CampusHTML.matches("[\"']sesskey[\"']\\s*:\\s*[\"']([A-Za-z0-9]+)[\"']", home).first?[1] else { throw CampusError.login }
                var request = URLRequest(url: URL(string: "https://plato.pusan.ac.kr/lib/ajax/service.php?sesskey=\(key)")!)
                request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [["index": 0, "methodname": "core_course_get_enrolled_courses_by_timeline_classification", "args": ["classification": "all", "limit": 0, "offset": 0, "sort": "fullname"]]])
                let (data, response) = try await session!.data(for: request); try validate(response)
                struct Envelope: Decodable { let error: Bool; let data: Courses? }; struct Courses: Decodable { let courses: [CampusCourse] }
                guard let envelope = try JSONDecoder().decode([Envelope].self, from: data).first, !envelope.error, let courses = envelope.data?.courses else { throw CampusError.login }
                state.courses = courses
                let currentTerm = courses.compactMap { $0.identity?.term }.max()
                for course in courses where course.identity?.term == currentTerm && currentTerm != nil {
                    try Task.checkCancellation()
                    status = course.fullname
                    let page = try await html("https://plato.pusan.ac.kr/course/view.php?id=\(course.id)&mode=sections")
                    let resources = CampusHTML.resources(page); state.resources[String(course.id)] = resources
                    for item in resources {
                        var detail: String?
                        if item.kind == "assign" || item.kind == "page" || item.kind == "url" {
                            detail = try await html(item.url)
                            let folder = try courseFolder(course, root: root).appendingPathComponent("일정")
                            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            try Data(CampusHTML.text(detail!).utf8).write(to: folder.appendingPathComponent("\(item.kind)_\(item.id).txt"), options: .atomic)
                        }
                        do {
                            let urls: [URL]
                            if item.kind == "ubfile" { urls = [URL(string: "https://plato.pusan.ac.kr/local/csmsdoc/download.php?id=\(item.id)&tp=m&pg=ubfile")!] }
                            else if item.kind == "forum" {
                                let forum = try await html(item.url)
                                var attached = CampusHTML.pluginFiles(forum)
                                let discussions = Set(CampusHTML.matches("(?:https://plato\\.pusan\\.ac\\.kr)?/mod/forum/discuss\\.php\\?d=([0-9]+)", forum).map { $0[1] })
                                for id in discussions.sorted(by: { (Int($0) ?? 0) > (Int($1) ?? 0) }).prefix(20) {
                                    let notice = try await html("https://plato.pusan.ac.kr/mod/forum/discuss.php?d=\(id)")
                                    attached += CampusHTML.pluginFiles(notice)
                                    let folder = try courseFolder(course, root: root).appendingPathComponent("일정")
                                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                    try Data(CampusHTML.text(notice).utf8).write(to: folder.appendingPathComponent("notice_\(id).txt"), options: .atomic)
                                }
                                urls = Array(Set(attached))
                            } else if let detail { urls = CampusHTML.pluginFiles(detail) }
                            else { urls = CampusHTML.pluginFiles(try await html(item.url)) }
                            for url in urls {
                                if ["mp4", "mov", "m3u8", "mpd", "webm"].contains(url.pathExtension.lowercased()) { continue }
                                let identity = "\(course.identity!.term)/\(course.id)/\(item.kind)/\(item.id)/" + CoordinatedStore.digest(Data(url.absoluteString.utf8))
                                if !manual, let old = state.attachments[identity], Date().timeIntervalSince(old.checked) < 86400 { continue }
                                try await download(url, item: item, course: course, identity: identity, root: root)
                                try persist()
                            }
                        }
                    }
                    try persist()
                }
                // The authenticated student portal is fetched directly. Failed SSO does not discard PLATO downloads.
                if let currentTerm, let timetable = try? await PortalAPI.timetable(session: session!, term: currentTerm) {
                    let folder = root.appendingPathComponent(".inkdrive/campus"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try timetable.write(to: folder.appendingPathComponent("timetable-api.json"), options: .atomic)
                }
                if let timetable = try? await html("https://onestop.pusan.ac.kr/main"), timetable.contains("schedule-item") {
                    let folder = root.appendingPathComponent(".inkdrive/campus"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let rows = CampusHTML.matches("<tr\\b[^>]*>(.*?)</tr>", timetable).filter { $0[1].contains("schedule-item") }.map { CampusHTML.text($0[1]) }
                    try JSONEncoder().encode(rows).write(to: folder.appendingPathComponent("timetable.json"), options: .atomic)
                }
                for cookie in config.httpCookieStorage?.cookies ?? [] { await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
                state.lastChecked = Date(); try persist(); status = "확인 완료"
            } catch { status = error.localizedDescription }
        }
    }
    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw CampusError.response }
        guard http.url?.host == "plato.pusan.ac.kr" || http.url?.host == "onestop.pusan.ac.kr" else { throw CampusError.login }
        if http.url?.path.contains("login") == true { throw CampusError.login }
    }
    private func html(_ url: String) async throws -> String {
        guard let parsed = URL(string: url), parsed.scheme == "https", CampusRedirects.hosts.contains(parsed.host ?? "") else { throw CampusError.origin }
        let (bytes, response) = try await session!.data(from: parsed); try validate(response)
        guard bytes.count < 15_000_000, let text = String(data: bytes, encoding: .utf8) else { throw CampusError.response }
        if text.contains("name=\"loginform\"") || text.contains("id=\"loginbtn\"") { throw CampusError.login }; return text
    }
    private func courseFolder(_ course: CampusCourse, root: URL) throws -> URL {
        guard let identity = course.identity else { throw CampusError.response }
        let relative = "\(identity.term)/\(CampusHTML.safeName(course.fullname))_\(identity.code)"
        let folder = try FileNames.child(relative, in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(course).write(to: folder.appendingPathComponent(".campus-course.json"), options: .atomic)
        return folder
    }
    private func download(_ url: URL, item: CampusResource, course: CampusCourse, identity: String, root: URL) async throws {
        guard url.host == "plato.pusan.ac.kr", url.scheme == "https" else { throw CampusError.origin }
        var request = URLRequest(url: url); request.setValue(item.url, forHTTPHeaderField: "Referer")
        let (temp, response) = try await session!.download(for: request)
        defer { try? FileManager.default.removeItem(at: temp) }; try validate(response)
        let bytes = try Data(contentsOf: temp, options: .mappedIfSafe)
        let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        guard !bytes.isEmpty, bytes.count <= 256_000_000, response.mimeType != "text/html" || disposition.lowercased().contains("attachment") else { throw CampusError.file }
        let hash = CoordinatedStore.digest(bytes)
        if let old = state.attachments[identity], old.sha256 == hash, FileManager.default.fileExists(atPath: root.appendingPathComponent(old.path).path) {
            state.attachments[identity] = CampusAttachment(sha256: hash, path: old.path, checked: Date()); return
        }
        let folder = try courseFolder(course, root: root).appendingPathComponent("강의자료")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = CampusHTML.safeName(response.suggestedFilename ?? item.title), base = URL(fileURLWithPath: name)
        let filename = "\(base.deletingPathExtension().lastPathComponent)__\(item.id)__\(hash.prefix(12))" + (base.pathExtension.isEmpty ? "" : "." + base.pathExtension)
        let target = folder.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: target.path) {
            guard try FileHasher.digest(target) == hash else { throw InkError.conflict }
        } else { try bytes.write(to: target, options: .atomic) }
        state.attachments[identity] = CampusAttachment(sha256: hash, path: String(target.path.dropFirst(root.path.count + 1)), checked: Date())
    }
    func logout() {
        guard !running else { return }
        Task {
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            await webView.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
            for cookie in HTTPCookieStorage.shared.cookies ?? [] { HTTPCookieStorage.shared.deleteCookie(cookie) }
            status = "학교 로그인 후 확인"; webView.load(URLRequest(url: URL(string: "https://plato.pusan.ac.kr/")!))
        }
    }
}
