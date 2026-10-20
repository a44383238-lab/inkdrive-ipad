import Foundation
import CryptoKit
enum FileHasher {
    static func digest(_ url: URL) throws -> String {
        guard let input = InputStream(url: url) else { throw InkError.unavailable }
        input.open(); defer { input.close() }
        var hasher = SHA256(), buffer = [UInt8](repeating: 0, count: 262_144)
        while true {
            let count = input.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw input.streamError ?? InkError.unavailable }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
