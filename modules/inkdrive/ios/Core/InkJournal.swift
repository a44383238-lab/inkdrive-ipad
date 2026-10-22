import Foundation
import PencilKit

struct InkRecovery: Codable { let expected: String; let pdf: Data }

/// Device-local recovery survives failed iCloud writes and never travels with login credentials.
final class InkJournal: @unchecked Sendable {
    let file: URL
    init(documentURL: URL, directory: URL? = nil) throws {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("InkDrive/Recovery")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent(CoordinatedStore.digest(Data(documentURL.standardizedFileURL.path.utf8)) + ".json")
    }
    func read() throws -> InkRecovery? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(InkRecovery.self, from: Data(contentsOf: file))
    }
    func write(_ pdf: Data, expected: String) throws { try JSONEncoder().encode(InkRecovery(expected: expected, pdf: pdf)).write(to: file, options: .atomic) }
    func clear() throws { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
}

/// Content-addressed objects first, immutable descriptor last. Shared with the Windows reader.
final class InkCommitStore: @unchecked Sendable {
    // Publication uses an independent PDFModel on a utility executor. Mutable head state is serialized here.
    private let lock = NSRecursiveLock()
    let root: URL
    let documentURL: URL
    let libraryRoot: URL
    private var parent: String?
    private var revision = 0
    private let device: String
    init(root: URL, documentID: UUID, documentURL: URL) throws {
        self.documentURL = documentURL; libraryRoot = root
        self.root = root.appendingPathComponent(".inkdrive/documents/" + documentID.uuidString.lowercased())
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: "inkdrive.device") { device = stored }
        else { device = UUID().uuidString; defaults.set(device, forKey: "inkdrive.device") }
        let key = "inkdrive.head." + documentID.uuidString
        parent = defaults.string(forKey: key)
        // Each writer follows its own verified head; concurrent devices produce visible forks.
        if let parent, let bytes = try? Data(contentsOf: self.root.appendingPathComponent("commits/\(parent).json")), CoordinatedStore.digest(bytes) == parent,
           let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], let n = value["inkRevision"] as? Int { revision = n }
        else { parent = nil }
        let heads = try completeHeads()
        if heads.count == 1 {
            let head = heads[0]
            let descriptorData = try Data(contentsOf: self.root.appendingPathComponent("commits/\(head.hash).json"))
            let descriptor = try JSONSerialization.jsonObject(with: descriptorData) as? [String: Any]
            let fileSHA = (descriptor?["file"] as? [String: Any])?["sha256"] as? String
            if parent == nil || fileSHA == (try? FileHasher.digest(documentURL)) {
                parent = head.hash; revision = head.revision
            }
        }
    }
    private func completeHeads() throws -> [(hash: String, revision: Int)] {
        let folder = root.appendingPathComponent("commits")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        var graph: [String: (parents: [String], revision: Int)] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let hash = file.deletingPathExtension().lastPathComponent
            guard hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  let bytes = try? Data(contentsOf: file), CoordinatedStore.digest(bytes) == hash,
                  let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any], value["format"] as? String == "inkdrive.commit",
                  let parents = value["parents"] as? [String], parents.count <= 1 else { continue }
            var valid = true, inkRevision = 0
            for key in ["source", "ink", "native"] + (value["preview"] == nil ? [] : ["preview"]) {
                guard let ref = value[key] as? [String: Any], let sha = ref["sha256"] as? String,
                      sha.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, let size = ref["bytes"] as? Int, size > 0, size <= 256_000_000,
                      let object = try? Data(contentsOf: root.appendingPathComponent("objects/" + sha)), object.count == size, CoordinatedStore.digest(object) == sha
                else { valid = false; break }
                if key == "ink", let ink = try? JSONDecoder().decode(PortableInkDocument.self, from: object) { inkRevision = ink.inkRevision }
            }
            if valid { graph[hash] = (parents, inkRevision) }
        }
        var changed = true
        while changed { changed = false; for (hash, node) in graph where node.parents.contains(where: { graph[$0] == nil }) { graph.removeValue(forKey: hash); changed = true } }
        let ancestors = Set(graph.values.flatMap { $0.parents })
        return graph.filter { !ancestors.contains($0.key) }.map { ($0.key, $0.value.revision) }
    }
    func checkHead() throws {
        lock.lock(); defer { lock.unlock() }
        let heads = try completeHeads()
        if heads.count > 1 || (heads.count == 1 && parent != heads[0].hash) { throw InkError.conflict }
    }
    private func object(_ bytes: Data) throws -> [String: Any] {
        let hash = CoordinatedStore.digest(bytes), folder = root.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(hash)
        if FileManager.default.fileExists(atPath: target.path) {
            guard try Data(contentsOf: target) == bytes else { throw InkError.conflict }
        } else { try bytes.write(to: target, options: .atomic) }
        return ["sha256": hash, "bytes": bytes.count]
    }
    func publish(_ model: PDFModel, fileBytes: Data) throws {
        lock.lock(); defer { lock.unlock() }
        let preview = try model.snapshot(includeInk: false)
        let adapterURL = URL(fileURLWithPath: documentURL.path + ".adapter.json")
        let adapter = FileManager.default.fileExists(atPath: adapterURL.path) ? try JSONDecoder().decode(DocumentAdapter.self, from: Data(contentsOf: adapterURL)) : nil
        let source: Data
        if let adapter {
            let original = try FileNames.child(adapter.originalPath, in: libraryRoot)
            source = try Data(contentsOf: original)
            guard CoordinatedStore.digest(source) == adapter.originalSHA256 else { throw InkError.conflict }
        } else { source = preview }
        let sourceHash = CoordinatedStore.digest(source)
        let now = Date(), born = model.pages.flatMap { $0.drawing.strokes.map { $0.path.creationDate } }.min() ?? now
        let documents = try model.pages.map { page in
            try PortableInkExporter.document(drawing: page.drawing, documentID: model.documentID, pageID: page.id,
                strokeIDs: PortableInkExporter.stableIDs(page.drawing, pageID: page.id), sourceSHA256: sourceHash,
                crop: page.page.bounds(for: .cropBox), rotation: ((page.page.rotation % 360) + 360) % 360,
                revision: revision + 1, createdAt: born, now: now)
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let pages = try documents.flatMap(\.pages).enumerated().map { index, page in try adapter?.convert(page, index: index) ?? page }
        var ink = PortableInkDocument(format: "inkdrive.ink", version: 1, documentId: model.documentID.uuidString.lowercased(), sourceRevision: sourceHash,
            inkRevision: revision + 1, createdAt: formatter.string(from: born), updatedAt: formatter.string(from: now),
            layers: [PortableInkLayer(id: "main", name: "필기", visible: true)], pages: pages)
        if adapter != nil { ink.previewRevision = CoordinatedStore.digest(preview) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let archives = try Dictionary(uniqueKeysWithValues: model.pages.map { ($0.id.uuidString.lowercased(), try encoder.encode(NativeInkArchive($0.drawing)).base64EncodedString()) })
        var descriptor: [String: Any] = ["format": "inkdrive.commit", "version": 1, "documentId": model.documentID.uuidString.lowercased(),
            "deviceId": device, "createdAt": formatter.string(from: now), "parents": parent.map { [$0] } ?? [], "inkRevision": revision + 1,
            "source": try object(source), "ink": try object(encoder.encode(ink)), "native": try object(encoder.encode(archives)),
            "nativeEncoding": "inkdrive.archive.v1",
            "file": ["path": String(documentURL.path.dropFirst(libraryRoot.path.count + 1)), "sha256": CoordinatedStore.digest(fileBytes)]]
        if adapter != nil { descriptor["preview"] = try object(preview) }
        let bytes = try JSONSerialization.data(withJSONObject: descriptor, options: [.sortedKeys, .withoutEscapingSlashes])
        let hash = CoordinatedStore.digest(bytes), commits = root.appendingPathComponent("commits")
        try FileManager.default.createDirectory(at: commits, withIntermediateDirectories: true)
        try bytes.write(to: commits.appendingPathComponent(hash + ".json"), options: .atomic)
        parent = hash; revision += 1
        UserDefaults.standard.set(hash, forKey: "inkdrive.head." + model.documentID.uuidString)
    }
}
