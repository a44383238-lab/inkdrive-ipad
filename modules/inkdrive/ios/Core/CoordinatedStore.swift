import Foundation
import CryptoKit

struct FileSnapshot { let data: Data; let digest: String }
protocol PDFStorage {
    var url: URL { get }
    func read() async throws -> FileSnapshot
    func write(_ data: Data, expected: String) async throws -> String
}

final class SecurityScope {
    let url: URL
    private let active: Bool
    init(_ url: URL) { self.url = url; active = url.startAccessingSecurityScopedResource() }
    deinit { if active { url.stopAccessingSecurityScopedResource() } }
}

/// The serial queue owns only disk bytes. PDFKit objects stay on the main thread.
final class CoordinatedStore: PDFStorage {
    let url: URL
    private let scope: SecurityScope
    private let queue = DispatchQueue(label: "inkdrive.file-access", qos: .userInitiated)
    init(url: URL, scope: SecurityScope? = nil) {
        self.url = url; self.scope = scope ?? SecurityScope(url)
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func read() async throws -> FileSnapshot {
        try await perform {
            var coordinationError: NSError?
            var result: Result<FileSnapshot, Error> = .failure(InkError.unavailable)
            NSFileCoordinator().coordinate(readingItemAt: self.url, options: [], error: &coordinationError) { coordinated in
                result = Result {
                    guard (NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinated) ?? []).isEmpty else { throw InkError.conflict }
                    let data = try Data(contentsOf: coordinated)
                    return FileSnapshot(data: data, digest: Self.digest(data))
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }
    }
    func write(_ data: Data, expected: String) async throws -> String {
        try await perform {
            var coordinationError: NSError?
            var result: Result<String, Error> = .failure(InkError.unavailable)
            NSFileCoordinator().coordinate(writingItemAt: self.url, options: .forReplacing, error: &coordinationError) { coordinated in
                result = Result {
                    guard (NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinated) ?? []).isEmpty,
                          Self.digest(try Data(contentsOf: coordinated)) == expected else { throw InkError.conflict }
                    try data.write(to: coordinated, options: .atomic)
                    return Self.digest(data)
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }
    }
    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}
