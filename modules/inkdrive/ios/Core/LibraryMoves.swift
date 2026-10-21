import Foundation

extension LibraryRepository {
    /// A user-triggered move keeps lesson references and adapter sidecars together.
    /// All destinations are checked before the first mutation; failures roll back completed moves.
    func moveItems(_ paths: [String], into parent: String) throws -> [String: String] {
        let scope = try access(), target = try FileNames.child(parent, in: scope.url)
        guard (try target.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else { throw InkError.invalidName }
        let unique = Set(paths)
        let sources = unique.filter { path in !unique.contains(where: { path.hasPrefix($0 + "/") }) }.sorted()
        var mappings: [String: String] = [:], moves: [(URL, URL)] = []
        for path in sources {
            guard !path.isEmpty, !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }), parent != path, !parent.hasPrefix(path + "/") else { throw InkError.invalidName }
            let source = try FileNames.child(path, in: scope.url)
            let relative = parent.isEmpty ? source.lastPathComponent : parent + "/" + source.lastPathComponent
            if path == relative { continue }
            let destination = try FileNames.child(relative, in: scope.url)
            guard !moves.contains(where: { $0.1 == destination }), !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
            mappings[path] = relative; moves.append((source, destination))
            let sidecar = URL(fileURLWithPath: source.path + ".adapter.json")
            if FileManager.default.fileExists(atPath: sidecar.path) {
                let output = URL(fileURLWithPath: destination.path + ".adapter.json")
                guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
                moves.append((sidecar, output))
            }
        }
        func remap(_ path: String) -> String {
            for (from, to) in mappings { if path == from { return to }; if path.hasPrefix(from + "/") { return to + path.dropFirst(from.count) } }
            return path
        }
        func remapDictionary(_ values: [String: String]) throws -> [String: String] {
            var output: [String: String] = [:]
            for (path, value) in values {
                let next = remap(path)
                guard output[next] == nil else { throw InkError.conflict }
                output[next] = value
            }
            return output
        }
        let metadata = scope.url.appendingPathComponent(".inkdrive/lessons", isDirectory: true)
        var error: NSError?, result: Result<Void, Error> = .failure(InkError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: scope.url, options: [], error: &error) { _ in
            var completed: [(URL, URL)] = []
            var updates: [(before: URL, after: URL, old: Data, new: Data)] = []
            var attempted = Set<URL>()
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                var metadataIsDirectory: ObjCBool = false
                let files: [URL]
                if FileManager.default.fileExists(atPath: metadata.path, isDirectory: &metadataIsDirectory) {
                    guard metadataIsDirectory.boolValue else { throw InkError.serialization }
                    files = try FileManager.default.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil)
                } else { files = [] }
                for file in files where file.pathExtension == "json" {
                    let bytes = try Data(contentsOf: file); var lesson = try JSONDecoder().decode(LessonRecord.self, from: bytes)
                    let before = try encoder.encode(lesson)
                    lesson.pdf = remap(lesson.pdf); lesson.recordings = lesson.recordings.map(remap); lesson.materials = lesson.materials.map(remap)
                    if let hashes = lesson.sourceDigests { lesson.sourceDigests = try remapDictionary(hashes) }
                    if let timeline = lesson.recordingTimeline { lesson.recordingTimeline = try remapDictionary(timeline) }
                    let after = try encoder.encode(lesson)
                    if before != after { updates.append((file, file, bytes, after)) }
                }
                // Adapters may live beside moved notebooks or in the hidden preview cache.
                var enumerationError: Error?
                guard let walker = FileManager.default.enumerator(at: scope.url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw InkError.unavailable }
                var visited = 0
                while let file = walker.nextObject() as? URL {
                    visited += 1; guard visited <= 100_000 else { throw InkError.unavailable }
                    if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { walker.skipDescendants(); continue }
                    guard file.lastPathComponent.hasSuffix(".adapter.json") else { continue }
                    let bytes = try Data(contentsOf: file), adapter = try JSONDecoder().decode(DocumentAdapter.self, from: bytes)
                    let original = remap(adapter.originalPath)
                    guard original != adapter.originalPath else { continue }
                    guard var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw InkError.serialization }
                    object["originalPath"] = original
                    let encoded = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                    _ = try JSONDecoder().decode(DocumentAdapter.self, from: encoded)
                    let relative = String(file.path.dropFirst(scope.url.path.count + 1))
                    updates.append((file, try FileNames.child(remap(relative), in: scope.url), bytes, encoded))
                }
                if let enumerationError { throw enumerationError }
                for (from, to) in moves { try FileManager.default.moveItem(at: from, to: to); completed.append((from, to)) }
                for update in updates { attempted.insert(update.before); try update.new.write(to: update.after, options: .atomic) }
                result = .success(())
            } catch {
                let originalError = error
                var failures: [String] = []
                // Attempt every reversal even when one provider operation fails.
                for (from, to) in completed.reversed() {
                    do { try FileManager.default.moveItem(at: to, to: from) }
                    catch { failures.append(to.lastPathComponent + ": " + error.localizedDescription) }
                }
                for update in updates where attempted.contains(update.before) {
                    let file = FileManager.default.fileExists(atPath: update.before.path) ? update.before : update.after
                    if (try? Data(contentsOf: file)) == update.old { continue }
                    do { try update.old.write(to: file, options: .atomic) }
                    catch { failures.append(file.lastPathComponent + ": " + error.localizedDescription) }
                }
                if failures.isEmpty { result = .failure(originalError) }
                else {
                    let recovery = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("InkDrive/MoveRecovery", isDirectory: true)
                    try? FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
                    let record: [String: Any] = ["mappings": mappings, "failures": failures, "root": scope.url.path, "date": ISO8601DateFormatter().string(from: Date())]
                    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: recovery.appendingPathComponent(UUID().uuidString + ".json"), options: .atomic) }
                    result = .failure(NSError(domain: "InkDrive.Move", code: 1, userInfo: [NSLocalizedDescriptionKey: "이동 복구를 확인해 주세요. 파일은 삭제하지 않았어요. " + failures.joined(separator: "; ")])) }
            }
        }
        if let error { throw error }; try result.get()
        return mappings
    }
}
