import SwiftUI
import PDFKit

private let ink = Color(white: 0.91)
private let accent = Color(red: 1, green: 0.79, blue: 0.25)
private let canvas = Color(white: 0.12)

struct NativeIcon: View {
    let name: String
    var size: CGFloat = 22
    var body: some View {
        Group { if let image = InkIcons.image(name) { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: name).resizable().scaledToFit() } }
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct IconAction: View {
    let icon: String
    let label: String
    var highlighted = false
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { NativeIcon(name: icon, size: 19).frame(width: 44, height: 44).foregroundStyle(highlighted ? accent : ink.opacity(0.8)) }
            .buttonStyle(.plain).accessibilityLabel(label).disabled(disabled).opacity(disabled ? 0.3 : 1)
    }
}

struct LibraryRootView: View {
    @EnvironmentObject private var store: NativeLibraryStore
    @Environment(\.scenePhase) private var phase
    @State private var form: CreationRequest?
    @State private var category = 0
    @State private var fileFilter = 0
    @State private var selected = Set<String>()
    @State private var selecting = false
    @State private var showAdd = false
    @State private var showMove = false
    @State private var showSidebar = true
    @State private var sortRecent = false
    private let folderPalette = ["#B7A3F7", "#E88BBD", "#FFD05A", "#F2A752", "#8AE3A4", "#8DBCF0", "#C58AEF"]
    private var shown: [LibraryEntry] {
        let entries = category == 1 ? store.recent.map(store.entry) : category == 2 ? store.favorites.sorted().map { path in
            store.entries.first { $0.path == path } ?? store.entry(path)
        } : store.filtered
        let filtered = entries.filter { entry in
            (store.query.isEmpty || entry.displayName.localizedCaseInsensitiveContains(store.query)) &&
            (fileFilter == 0 || entry.directory || (fileFilter == 1 ? entry.path.lowercased().hasSuffix(".pdf") : !entry.path.lowercased().hasSuffix(".pdf")))
        }
        return sortRecent ? filtered.sorted { (store.recent.firstIndex(of: $0.path) ?? Int.max) < (store.recent.firstIndex(of: $1.path) ?? Int.max) } : filtered
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if showSidebar { sidebar.frame(width: min(230, max(180, geometry.size.width * 0.18))) }
                VStack(spacing: 0) {
                    header
                    if store.screen == .library { library }
                    else { ScrollView { Group {
                        if store.screen == .today { today }
                        else if store.screen == .campus { CampusPanel(campus: store.campus) }
                        else { settings }
                    }.padding(24) } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(canvas).foregroundStyle(ink)
        }
        .preferredColorScheme(.dark).tint(accent)
        .overlay(alignment: .bottomTrailing) { if store.busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(24) } }
        .disabled(store.busy)
        .alert("InkDrive", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("확인", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
        .sheet(isPresented: $showMove) { FolderDestinationView(paths: Array(selected)) { folder in
            do { try store.move(Array(selected), into: folder); selected.removeAll(); selecting = false; showMove = false }
            catch { store.message = error.localizedDescription }
        }.environmentObject(store) }
        .sheet(item: $form) { CreationSheet(request: $0).environmentObject(store) }
        .sheet(item: $store.textPreview) { value in
            NavigationStack { ScrollView { Text(value.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(24) }.navigationTitle(value.title).toolbar { ToolbarItem(placement: .topBarLeading) { Button { store.textPreview = nil } label: { NativeIcon(name: "arrow-left") }.accessibilityLabel("서재로") } } }
        }
        .fullScreenCover(item: $store.document) { document in EditorHost(store: store, document: document).ignoresSafeArea() }
        .sheet(item: $store.material) { document in
            if ["html", "htm"].contains(document.url.pathExtension.lowercased()) { HTMLMaterialView(document: document, store: store) }
            else { MaterialPreview(document: document) }
        }
        .onChange(of: phase) { _, value in if value == .active { store.date = NativeLibraryStore.today(); store.refresh(); if !ProcessInfo.processInfo.arguments.contains("--ui-smoke") { store.campus.checkIfDue() } } }
        .task { if !ProcessInfo.processInfo.arguments.contains("--ui-smoke") { store.campus.checkIfDue() } }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) { NativeIcon(name: "search", size: 14); TextField("검색", text: $store.query).font(.system(size: 12)).accessibilityLabel("파일 검색") }
                .foregroundStyle(.secondary).padding(9).background(.black, in: RoundedRectangle(cornerRadius: 3)).padding(.bottom, 6)
            navigation(.library, "book-open", "서재") { category = 0 }
            navigation(.today, "calendar-days", "수업") {}
            navigation(.campus, "globe", "학교") {}
            Button(action: store.chooseFolder) { Label("iCloud Drive", systemImage: "icloud").font(.system(size: 12)).padding(.vertical, 14) }.padding(.horizontal, 8)
            HStack(spacing: 12) {
                Button { category = 1; store.screen = .library } label: { Label("최근 목록", systemImage: "clock.fill") }
                Button { category = 2; store.screen = .library } label: { Label("즐겨찾기", systemImage: "star.fill") }
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(accent).padding(.top, 16).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 2) { ForEach(store.recent.prefix(15), id: \.self) { path in
                    Button { store.open(store.entry(path)) } label: {
                        HStack(spacing: 10) {
                            DocumentThumbnail(entry: store.entry(path)).frame(width: 23, height: 30)
                            Text(store.entry(path).displayName.replacingOccurrences(of: ".pdf", with: "")).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 0)
                        }.padding(.vertical, 6).padding(.horizontal, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } }
            }
            Spacer(minLength: 0)
            HStack { IconAction(icon: "settings-2", label: "설정") { store.screen = .settings }; Spacer(); IconAction(icon: "chevron-left", label: "사이드바 접기") { showSidebar = false } }
        }.padding(.horizontal, 12).padding(.top, 10).background(Color(white: 0.145))
    }
    private func navigation(_ screen: LibraryScreen, _ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { store.screen = screen; action(); store.refresh() } label: {
            HStack(spacing: 12) { NativeIcon(name: icon, size: 18); Text(label).font(.system(size: 13, weight: .medium)); Spacer() }
                .foregroundStyle(store.screen == screen ? accent : ink).padding(.horizontal, 9).frame(height: 40)
                .background(store.screen == screen ? .black : .clear, in: RoundedRectangle(cornerRadius: 3))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private var header: some View {
        HStack {
            if !showSidebar { IconAction(icon: "panel-left", label: "사이드바 펼치기") { showSidebar = true } }
            if store.screen == .library && !store.path.isEmpty { IconAction(icon: "chevron-left", label: "상위 폴더", action: store.parent) }
            Spacer()
            Text(store.screen == .library ? (category == 1 ? "최근 목록" : category == 2 ? "즐겨찾기" : store.breadcrumbs.last.map(LibraryEntry.folderTitle) ?? "문서") : store.screen == .today ? "수업" : store.screen == .campus ? "학교" : "설정").font(.system(size: 14, weight: .semibold))
            Spacer()
            if store.activeRecording {
                Button(action: store.stopRecording) { HStack(spacing: 5) { Image(systemName: "stop.circle.fill"); Text(RecordingBrowserController.timestamp(store.elapsed)).monospacedDigit().font(.system(size: 11)) }.foregroundStyle(.red).frame(minHeight: 44) }.accessibilityLabel("녹음 종료")
            }
            if store.screen == .library {
                IconAction(icon: selecting ? "x" : "circle-check", label: selecting ? "선택 완료" : "문서 선택") { selecting.toggle(); selected.removeAll() }
            }
        }.padding(.horizontal, 12).frame(height: 48)
    }
    private var library: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HStack {
                    if selecting {
                        Button("모두 선택") { selected = Set(shown.map(\.path)) }.font(.system(size: 12))
                        Text("\(selected.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        IconAction(icon: "folder-open", label: "선택한 문서 이동", disabled: selected.isEmpty) { showMove = true }
                        Button { for path in selected { store.toggleFavorite(path) }; selecting = false; selected.removeAll() } label: { NativeIcon(name: "star", size: 18).frame(width: 44, height: 44) }.accessibilityLabel("선택한 문서 즐겨찾기 전환")
                    } else {
                        Spacer()
                        ForEach(Array(["전체", "PDF", "자료"].enumerated()), id: \.offset) { index, name in
                            Button(name) { fileFilter = index }.font(.system(size: 12, weight: fileFilter == index ? .semibold : .regular)).foregroundStyle(fileFilter == index ? accent : Color.secondary).frame(minWidth: 36, minHeight: 44)
                        }
                        Spacer()
                        IconAction(icon: "arrow-down-wide-narrow", label: "최근 사용순 정렬") { sortRecent.toggle() }
                    }
                }.padding(.horizontal, 20).frame(height: 38)
                if !store.hasRoot {
                    VStack(spacing: 22) { FolderGlyph(color: Color(red: 0.72, green: 0.64, blue: 0.97)).frame(width: 100, height: 82); Button("폴더 연결", action: store.chooseFolder).buttonStyle(.bordered).tint(accent) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112, maximum: 154), spacing: 24)], alignment: .leading, spacing: 28) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in tile(entry, index: index) }
                        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 100)
                        if shown.isEmpty { Text("비어 있어요").font(.system(size: 12)).foregroundStyle(.secondary).padding(50) }
                    }
                }
            }
            if showAdd {
                VStack(alignment: .trailing, spacing: 10) {
                    addAction("새 폴더", "folder-plus") { form = CreationRequest(folder: true) }
                    addAction("새 노트", "file-text") { form = CreationRequest(folder: false) }
                    addAction("PDF 가져오기", "square.and.arrow.down") { store.choosePDF() }
                }.padding(.trailing, 28).padding(.bottom, 86).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button { withAnimation(.easeOut(duration: 0.18)) { showAdd.toggle() } } label: {
                NativeIcon(name: showAdd ? "x" : "plus", size: 28).foregroundStyle(.white).frame(width: 54, height: 54).background(accent, in: Circle()).shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }.accessibilityLabel("새 문서 메뉴").padding(24)
        }
    }
    private func addAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button { showAdd = false; action() } label: { HStack(spacing: 12) { Text(title).font(.system(size: 13)); NativeIcon(name: icon, size: 18).frame(width: 40, height: 40).background(accent, in: Circle()) }.foregroundStyle(.white).padding(.leading, 14).background(Color(white: 0.18), in: Capsule()) }.disabled(!store.hasRoot && icon != "square.and.arrow.down")
    }
    private func tile(_ entry: LibraryEntry, index: Int) -> some View {
        VStack(spacing: 8) {
            Button {
                if selecting { if selected.contains(entry.path) { selected.remove(entry.path) } else { selected.insert(entry.path) } }
                else { store.open(entry) }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if entry.directory { FolderGlyph(color: Color(uiColor: UIColor(hex: store.folderColors[entry.path] ?? folderPalette[entry.path.utf8.reduce(0) { ($0 + Int($1)) % folderPalette.count }]))).frame(width: 104, height: 82) }
                        else { DocumentThumbnail(entry: entry).shadow(color: .black.opacity(0.18), radius: 2, y: 1) }
                    }.frame(maxWidth: .infinity).frame(height: 148)
                    if store.favorites.contains(entry.path) { Image(systemName: "star.fill").font(.system(size: 17)).foregroundStyle(entry.directory ? Color.pink : accent).offset(x: -3, y: -2) }
                    if selecting { Image(systemName: selected.contains(entry.path) ? "checkmark.circle.fill" : "circle.fill").foregroundStyle(selected.contains(entry.path) ? accent : .white).background(Circle().stroke(.black, lineWidth: 1)).offset(x: -5, y: 125) }
                }.opacity(selecting && !selected.contains(entry.path) ? 0.55 : 1)
            }.buttonStyle(.plain).accessibilityLabel(entry.displayName)
            HStack(spacing: 3) {
                Text(entry.displayName.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 29)
                Menu {
                    Button("이동") { selected = [entry.path]; showMove = true }
                    Button(store.favorites.contains(entry.path) ? "즐겨찾기 해제" : "즐겨찾기") { store.toggleFavorite(entry.path) }
                    if entry.directory { ForEach(folderPalette, id: \.self) { color in Button(color) { store.setFolderColor(color, path: entry.path) } } }
                } label: { NativeIcon(name: "chevron-down", size: 12).foregroundStyle(.secondary).frame(width: 26, height: 32) }.accessibilityLabel(entry.displayName + " 메뉴")
            }
        }.frame(maxWidth: .infinity)
    }
    private var today: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.date).font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(store.lessons, id: \.id) { lesson in
                HStack { VStack(alignment: .leading, spacing: 6) { Text(lesson.subject).font(.caption).foregroundStyle(.secondary); Text(lesson.title).font(.system(size: 14)) }; Spacer()
                    IconAction(icon: "pen-tool", label: "필기 열기") { store.document = OpenDocument(path: lesson.pdf, externalURL: nil) }
                    IconAction(icon: "play", label: "녹음본 듣기", disabled: lesson.recordings.isEmpty || store.activeRecording) { do { try store.showRecordings(lesson.pdf) } catch { store.message = error.localizedDescription } }
                }.padding(16).background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.rootName ?? "연결 안 됨").font(.headline)
            Button("폴더 선택", action: store.chooseFolder).disabled(store.activeRecording)
            Text("22:00 · 전사 · 노트 · 문제").font(.system(size: 13)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FolderGlyph: View {
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.85)).frame(width: g.size.width * 0.5, height: g.size.height * 0.3)
                RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.8)).padding(.top, g.size.height * 0.12)
                RoundedRectangle(cornerRadius: 5).fill(color).padding(.top, g.size.height * 0.24)
            }
        }.accessibilityHidden(true)
    }
}

private struct DocumentThumbnail: View {
    @EnvironmentObject private var store: NativeLibraryStore
    let entry: LibraryEntry
    @State private var image: UIImage?
    private static let cache = NSCache<NSString, UIImage>()
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { NativeIcon(name: "file-text", size: 28).foregroundStyle(Color.gray).frame(width: 80, height: 112).background(Color(white: 0.92), in: RoundedRectangle(cornerRadius: 3)) } }
            .task(id: entry.path + String(store.libraryRevision)) {
                guard entry.path.lowercased().hasSuffix(".pdf"), let scope = try? store.repository.access(), let url = try? FileNames.child(entry.path, in: scope.url) else { return }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let key = (url.path + String(date)) as NSString
                if let cached = Self.cache.object(forKey: key) { image = cached; return }
                // Render only visible LazyVGrid cells; never hydrate every iCloud document at startup.
                await Task.yield()
                guard !Task.isCancelled, let snapshot = try? await CoordinatedStore(url: url, scope: scope).read(), !Task.isCancelled, let page = PDFDocument(data: snapshot.data)?.page(at: 0) else { return }
                let preview = page.thumbnail(of: CGSize(width: 240, height: 296), for: .cropBox)
                Self.cache.countLimit = 80; Self.cache.setObject(preview, forKey: key); image = preview
                withExtendedLifetime(scope) {}
            }
    }
}

private struct FolderDestinationView: View {
    @EnvironmentObject private var store: NativeLibraryStore
    @Environment(\.dismiss) private var dismiss
    let paths: [String]
    let move: (String) -> Void
    @State private var path = ""
    @State private var folders: [LibraryEntry] = []
    private var allowed: Bool { !paths.contains { path == $0 || path.hasPrefix($0 + "/") } }
    var body: some View {
        NavigationStack {
            List {
                if !path.isEmpty { Button { path = path.split(separator: "/").dropLast().joined(separator: "/"); refresh() } label: { Label("상위 폴더", systemImage: "chevron.left") } }
                ForEach(folders) { entry in
                    Button { path = entry.path; refresh() } label: { HStack { Image(systemName: "folder.fill").foregroundStyle(.purple); Text(entry.displayName); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) } }
                }
            }.navigationTitle(path.isEmpty ? store.rootName ?? "InkDrive" : LibraryEntry.folderTitle(URL(fileURLWithPath: path).lastPathComponent))
                .navigationBarTitleDisplayMode(.inline).toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("여기로 이동") { move(path) }.disabled(!allowed) }
                }
        }.preferredColorScheme(.dark).presentationDetents([.large]).task { refresh() }
    }
    private func refresh() {
        do {
            folders = try store.repository.list(path).compactMap { value in
                guard value["directory"] as? Bool == true, let name = value["name"] as? String, let relative = value["path"] as? String, !paths.contains(where: { relative == $0 || relative.hasPrefix($0 + "/") }) else { return nil }
                return LibraryEntry(name: name, path: relative, directory: true)
            }.sorted { $0.displayName < $1.displayName }
        } catch { store.message = error.localizedDescription }
    }
}

struct CreationRequest: Identifiable { let id = UUID(); let folder: Bool }
struct CreationSheet: View {
    let request: CreationRequest
    @EnvironmentObject private var store: NativeLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var template = PaperTemplate.ruled
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("이름", text: $name).accessibilityLabel("이름")
                if !request.folder { Picker("종이", selection: $template) { Text("무지").tag(PaperTemplate.plain); Text("줄노트").tag(PaperTemplate.ruled); Text("모눈").tag(PaperTemplate.grid); Text("노란 줄노트").tag(PaperTemplate.yellowRuled) }.pickerStyle(.segmented) }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.subheadline) }
            }.navigationTitle(request.folder ? "새 폴더" : "새 노트").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("만들기") { do { try store.create(name: name, folder: request.folder, template: template); dismiss() } catch { self.error = error.localizedDescription } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.presentationDetents([.medium])
    }
}
