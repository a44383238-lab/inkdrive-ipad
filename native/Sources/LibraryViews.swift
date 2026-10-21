import SwiftUI

private let ink = Color(red: 0.15, green: 0.21, blue: 0.31)
private let accent = Color(red: 0.21, green: 0.40, blue: 0.75)
private let canvas = Color(red: 0.97, green: 0.98, blue: 0.99)

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
        Button(action: action) { NativeIcon(name: icon).frame(width: 44, height: 44).foregroundStyle(highlighted ? .white : ink.opacity(0.7)).background(highlighted ? accent : Color(red: 0.93, green: 0.95, blue: 0.97), in: RoundedRectangle(cornerRadius: 13)) }
            .buttonStyle(.plain).accessibilityLabel(label).disabled(disabled).opacity(disabled ? 0.35 : 1)
    }
}
struct LibraryRootView: View {
    @EnvironmentObject private var store: NativeLibraryStore
    @Environment(\.scenePhase) private var phase
    @State private var form: CreationRequest?
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                NativeIcon(name: "pen-tool", size: 24).foregroundStyle(.white).frame(width: 44, height: 44).background(accent, in: RoundedRectangle(cornerRadius: 15)).padding(.bottom, 22)
                nav(.library, "book-open", "서재")
                nav(.today, "calendar-days", "수업")
                nav(.campus, "globe", "학교")
                Spacer()
                nav(.settings, "settings-2", "설정")
            }.padding(.vertical, 24).frame(width: 80).background(Color(red: 0.93, green: 0.95, blue: 0.97))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.activeRecording {
                        HStack {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text(RecordingBrowserController.timestamp(store.elapsed)).monospacedDigit().font(.subheadline)
                            Spacer()
                            IconAction(icon: "square", label: "녹음 종료", action: store.stopRecording)
                        }.padding(12).background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if store.pendingRecording && !store.activeRecording {
                        HStack { Text("미완료 녹음").font(.subheadline); Spacer(); Button("복구", action: store.recoverRecording) }
                            .padding(14).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }
                    HStack {
                        Text(store.screen == .library ? "서재" : store.screen == .today ? "수업" : store.screen == .campus ? "학교" : "설정").font(.system(size: 30, weight: .bold))
                        Spacer()
                        if store.screen == .library {
                            IconAction(icon: "folder-plus", label: "새 폴더", disabled: !store.hasRoot) { form = CreationRequest(folder: true) }
                            IconAction(icon: "file-text", label: "PDF 열기", action: store.choosePDF)
                            IconAction(icon: "plus", label: "새 노트", highlighted: true, disabled: !store.hasRoot) { form = CreationRequest(folder: false) }
                        }
                    }
                    if store.screen == .library { library }
                    else if store.screen == .today { today }
                    else if store.screen == .campus { CampusPanel(campus: store.campus) }
                    else { settings }
                }.padding(32).frame(maxWidth: 1240, alignment: .leading).frame(maxWidth: .infinity)
            }.background(canvas)
        }.foregroundStyle(ink)
        .overlay(alignment: .bottomTrailing) { if store.busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(24) } }
        .disabled(store.busy)
        .alert("InkDrive", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("확인", role: .cancel) { store.message = nil } } message: { Text(store.message ?? "") }
        .sheet(item: $form) { request in CreationSheet(request: request).environmentObject(store) }
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
    private func nav(_ screen: LibraryScreen, _ icon: String, _ label: String) -> some View {
        Button { store.screen = screen; store.refresh() } label: {
            NativeIcon(name: icon, size: 23).foregroundStyle(store.screen == screen ? accent : ink.opacity(0.5)).frame(width: 48, height: 48)
                .background(store.screen == screen ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(store.screen == screen ? .isSelected : [])
    }
    @ViewBuilder private var library: some View {
        if !store.hasRoot {
            VStack(spacing: 24) { folderArt(size: 130); Button("폴더 연결", action: store.chooseFolder).buttonStyle(.borderedProminent).tint(accent) }
                .frame(maxWidth: .infinity, minHeight: 350)
        } else {
            HStack(spacing: 10) {
                IconAction(icon: "arrow-left", label: "상위 폴더", disabled: store.path.isEmpty, action: store.parent)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button(store.rootName ?? "InkDrive") { store.navigate("") }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        ForEach(Array(store.breadcrumbs.enumerated()), id: \.offset) { index, part in
                            NativeIcon(name: "chevron-right", size: 14).foregroundStyle(.secondary)
                            Button(part) { store.navigate(store.breadcrumbs.prefix(index + 1).joined(separator: "/")) }.font(.subheadline).frame(minHeight: 44)
                        }
                    }
                }
                HStack(spacing: 8) { NativeIcon(name: "search", size: 18).foregroundStyle(.secondary); TextField("검색", text: $store.query).font(.subheadline).accessibilityLabel("파일 검색") }
                    .padding(.horizontal, 12).frame(width: 190, height: 44).background(.white, in: RoundedRectangle(cornerRadius: 13))
            }.tint(ink.opacity(0.8))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 144, maximum: 165), spacing: 18)], alignment: .leading, spacing: 18) {
                ForEach(store.filtered) { entry in
                    Button { store.open(entry) } label: {
                        VStack(spacing: 14) {
                            if entry.directory { folderArt(size: 108) }
                            else { NativeIcon(name: "file-text", size: 42).foregroundStyle(accent.opacity(0.6)).frame(width: 68, height: 86).background(canvas, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.08))) }
                            Text(entry.name.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).frame(height: 36)
                        }.frame(maxWidth: .infinity).padding(.vertical, 16).padding(.horizontal, 8).background(.white, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(ink.opacity(0.07)))
                    }.buttonStyle(.plain).accessibilityLabel(entry.name)
                }
            }
            if store.filtered.isEmpty { Text(store.query.isEmpty ? "비어 있어요" : "검색 결과 없음").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180) }
        }
    }
    private var today: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(store.date).font(.subheadline).foregroundStyle(.secondary); Spacer(); IconAction(icon: "folder-open", label: "정리 결과", disabled: !store.hasRoot) { store.screen = .library; store.navigate("AI") } }
            if store.lessons.isEmpty { Text("수업 없음").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200) }
            ForEach(store.lessons, id: \.id) { lesson in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) { Text(lesson.subject).font(.caption).foregroundStyle(.secondary); Text(lesson.title).font(.headline) }
                        Spacer(); Text(lesson.endedAt == nil ? "진행 중" : "종료").font(.caption).padding(8).background(canvas, in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 8) {
                        IconAction(icon: "pen-tool", label: "필기 열기") { store.document = OpenDocument(path: lesson.pdf, externalURL: nil) }
                        IconAction(icon: "play", label: "녹음본 듣기", disabled: lesson.recordings.isEmpty || store.activeRecording) { do { try store.showRecordings(lesson.pdf) } catch { store.message = error.localizedDescription } }
                        IconAction(icon: "plus", label: "녹음 가져오기", disabled: store.activeRecording) { store.importRecording(lesson) }
                        Button(lesson.endedAt == nil ? "수업 종료" : "다시 열기") { store.finishLesson(lesson) }.buttonStyle(.bordered).tint(accent).frame(minHeight: 44)
                    }
                }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) { Text(store.rootName ?? "연결 안 됨").font(.headline); Button("폴더 선택", action: store.chooseFolder).buttonStyle(.bordered).tint(accent).disabled(store.activeRecording) }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 10) { Text("22:00").font(.title2.weight(.semibold)); Text("전사 · 노트 · 문제").font(.subheadline).foregroundStyle(.secondary) }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private func folderArt(size: CGFloat) -> some View {
        Group { if let image = UIImage(named: "folder-art") { Image(uiImage: image).resizable().scaledToFit() } }
            .frame(width: size, height: size * 0.8).accessibilityHidden(true)
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
                if !request.folder { Picker("종이", selection: $template) { Text("무지").tag(PaperTemplate.plain); Text("줄노트").tag(PaperTemplate.ruled); Text("모눈").tag(PaperTemplate.grid) }.pickerStyle(.segmented) }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.subheadline) }
            }.navigationTitle(request.folder ? "새 폴더" : "새 노트").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("취소") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("만들기") { do { try store.create(name: name, folder: request.folder, template: template); dismiss() } catch { self.error = error.localizedDescription } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.presentationDetents([.medium])
    }
}
