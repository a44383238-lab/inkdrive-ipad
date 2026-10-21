import Foundation
import Security

/// Recreates the school's published gfn_ajax request envelope with fresh page RSA/CSRF values.
enum PortalAPI {
    private static func der(_ tag: UInt8, _ data: Data) -> Data {
        let count = data.count
        var length = Data()
        if count < 128 { length.append(UInt8(count)) }
        else {
            var n = count, digits: [UInt8] = []
            while n > 0 { digits.insert(UInt8(n & 255), at: 0); n >>= 8 }
            length.append(0x80 | UInt8(digits.count)); length.append(contentsOf: digits)
        }
        return Data([tag]) + length + data
    }
    private static func hex(_ string: String) throws -> Data {
        guard !string.isEmpty, string.count % 2 == 0 else { throw CampusError.response }
        var bytes = Data(), cursor = string.startIndex
        while cursor < string.endIndex { let end = string.index(cursor, offsetBy: 2); guard let byte = UInt8(string[cursor..<end], radix: 16) else { throw CampusError.response }; bytes.append(byte); cursor = end }
        return bytes
    }
    static func encrypt(_ string: String, modulus: String, exponent: String) throws -> String {
        func integer(_ value: Data) -> Data { der(2, value.first.map { $0 & 0x80 != 0 } == true ? Data([0]) + value : value) }
        let n = try hex(modulus), e = try hex(exponent.count % 2 == 0 ? exponent : "0" + exponent)
        let keyData = der(0x30, integer(n) + integer(e))
        let attrs: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, nil) else { throw CampusError.response }
        let limit = min(200, SecKeyGetBlockSize(key) - 11)
        var chunks: [Data] = [], current = Data()
        for character in string {
            let bytes = Data(String(character).utf8)
            if current.count + bytes.count > limit { chunks.append(current); current = Data() }
            current.append(bytes)
        }
        if !current.isEmpty { chunks.append(current) }
        return try chunks.map { bytes in
            guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, bytes as CFData, nil) as Data? else { throw CampusError.response }
            return encrypted.map { String(format: "%02x", $0) }.joined()
        }.joined(separator: ",")
    }
    static func timetable(session: URLSession, term: String) async throws -> Data {
        let base = "https://onestop.pusan.ac.kr"
        let (bytes, _) = try await session.data(from: URL(string: base + "/main")!)
        guard let html = String(data: bytes, encoding: .utf8),
              let modulus = CampusHTML.matches("RSAModulus\\s*=\\s*['\"]([0-9a-f]+)['\"]", html).first?[1],
              let exponent = CampusHTML.matches("RSAExponent\\s*=\\s*['\"]([0-9a-f]+)['\"]", html).first?[1],
              let csrf = CampusHTML.matches("scwin\\.token\\s*=\\s*['\"]([^'\"]+)['\"]", html).first?[1] else { throw CampusError.login }
        func post(_ path: String, _ query: [String: Any], auth: Any? = nil) async throws -> [String: Any] {
            var inner = query; inner["locale"] = "0001"
            var envelope: [String: Any] = ["_data": String(data: try JSONSerialization.data(withJSONObject: inner), encoding: .utf8)!]
            if let auth { envelope["AUTH_STR"] = auth }
            let encrypted = try encrypt(String(data: JSONSerialization.data(withJSONObject: envelope), encoding: .utf8)!, modulus: modulus, exponent: exponent)
            var request = URLRequest(url: URL(string: base + path)!)
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("true", forHTTPHeaderField: "AJAX"); request.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["_data": encrypted])
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], String(describing: result["statusCode"] ?? "") != "440" else { throw CampusError.login }
            return result
        }
        let info = try await post("/global/info", ["menuCD": "000000000000000"])
        guard info["_LoginUser"] != nil else { throw CampusError.login }
        let menus = info["_Menu"] as? [[String: Any]] ?? []
        let menu = menus.first { $0.values.contains { String(describing: $0).contains("persontimetablesearch") } }
        let year = String(term.prefix(4)), semester = String(term.suffix(4))
        let result = try await post("/ost/cls/timetablesearch/persontimetablesearch/selectPersonTimetable", ["SCH_SYEAR": year, "SCH_TERM_GCD": semester, "SYEAR": year, "TERM_GCD": semester], auth: menu?["AUTH_STR"])
        guard let rows = result["data"] as? [[String: Any]] else { throw CampusError.response }
        return try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys, .prettyPrinted])
    }
}
