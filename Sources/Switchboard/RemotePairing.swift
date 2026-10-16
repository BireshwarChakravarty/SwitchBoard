import Foundation
import CryptoKit

/// Pairing for the iPhone remote.
///
/// The Mac shows a six-digit code. A phone that sends it gets a long random
/// key, which it then sends with every request. Only SHA-256 hashes of keys
/// are stored. A wrong code counts against the current code; after a few
/// misses it's replaced, so the code can't be guessed by trying them all.
struct RemotePairing {
    static let maximumAttempts = 5

    private(set) var code: String
    private(set) var keyHashes: Set<String>
    private var failedAttempts = 0

    init(keyHashes: Set<String> = []) {
        self.code = Self.newCode()
        self.keyHashes = keyHashes
    }

    enum PairResult: Equatable {
        case paired(key: String)
        case wrongCode
        /// Too many wrong codes: the code was replaced.
        case codeReplaced
    }

    /// Check a code; on success, issue a key and replace the code.
    mutating func pair(with attempt: String) -> PairResult {
        let digits = attempt.filter(\.isNumber)
        guard digits == code else {
            failedAttempts += 1
            if failedAttempts >= Self.maximumAttempts {
                renewCode()
                return .codeReplaced
            }
            return .wrongCode
        }
        let key = issueKey()
        renewCode()
        return .paired(key: key)
    }

    /// A new key, without a code (for shortcuts made on the Mac itself).
    mutating func issueKey() -> String {
        let key = Self.newKey()
        keyHashes.insert(Self.hash(key))
        return key
    }

    mutating func revoke(key: String) {
        keyHashes.remove(Self.hash(key))
    }

    func accepts(key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        return keyHashes.contains(Self.hash(key))
    }

    mutating func renewCode() {
        code = Self.newCode()
        failedAttempts = 0
    }

    mutating func forgetAllKeys() {
        keyHashes = []
    }

    /// The key a request carries: `Authorization: Bearer <key>`,
    /// `X-Switchboard-Key: <key>`, or `?key=<key>` (handy in Shortcuts).
    static func key(in request: HTTPRequest) -> String? {
        if let authorization = request.headers["authorization"],
           authorization.lowercased().hasPrefix("bearer ") {
            return String(authorization.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        }
        return request.headers["x-switchboard-key"] ?? request.query["key"]
    }

    static func hash(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func newCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    /// 32 random bytes as hex. `SystemRandomNumberGenerator` is
    /// cryptographically secure on Apple platforms.
    private static func newKey() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }
}
