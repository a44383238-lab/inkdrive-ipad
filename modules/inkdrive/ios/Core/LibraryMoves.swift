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
        let metadata = scope.url.appendingPathComponent(".inkdrive/lessons", isDirectory: true)
        var error: NSError?, result: Result<Void, Error> = .failure(InkError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: scope.url, options: [], error: &error) { _ in
            var completed: [(URL, URL)] = [], originals: [(URL, Data)] = []
            do {
                let files = (try? FileManager.default.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil)) ?? []
                var updates: [(URL, Data)] = []
                for file in files where file.pathExtension == "json" {
                    let bytes = try Data(contentsOf: file); var lesson = try JSONDecoder().decode(LessonRecord.self, from: bytes)
                    lesson.pdf = remap(lesson.pdf); lesson.recordings = lesson.recordings.map(remap); lesson.materials = lesson.materials.map(remap)
                    if let hashes = lesson.sourceDigests { lesson.sourceDigests = Dictionary(uniqueKeysWithValues: hashes.map { (remap($0.key), $0.value) }) }
                    if let timeline = lesson.recordingTimeline { lesson.recordingTimeline = Dictionary(uniqueKeysWithValues: timeline.map { (remap($0.key), $0.value) }) }
                    originals.append((file, bytes)); updates.append((file, try JSONEncoder().encode(lesson)))
                }
                for (from, to) in moves { try FileManager.default.moveItem(at: from, to: to); completed.append((from, to)) }
                for (file, bytes) in updates { try bytes.write(to: file, options: .atomic) }
                result = .success(())
            } catch {
                let originalError = error
                do {
                    for (file, bytes) in originals { try bytes.write(to: file, options: .atomic) }
                    for (from, to) in completed.reversed() { try FileManager.default.moveItem(at: to, to: from) }
                    result = .failure(originalError)
                } catch { result = .failure(error) }
            }
        }
        if let error { throw error }; try result.get()
        return mappings
    }
}
