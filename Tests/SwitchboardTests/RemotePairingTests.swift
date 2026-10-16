import XCTest
@testable import Switchboard

/// Pairing codes and keys.
final class RemotePairingTests: XCTestCase {
    func testPairsWithTheRightCodeAndIssuesAKey() {
        var pairing = RemotePairing()
        let code = pairing.code
        XCTAssertEqual(code.count, 6)
        guard case .paired(let key) = pairing.pair(with: String(code.prefix(3)) + " " + String(code.suffix(3))) else {
            return XCTFail("didn't pair")
        }
        XCTAssertEqual(key.count, 64)
        XCTAssertTrue(pairing.accepts(key: key))
        XCTAssertFalse(pairing.accepts(key: "nope"))
        XCTAssertFalse(pairing.accepts(key: nil))
        XCTAssertFalse(pairing.keyHashes.contains(key), "keys are stored hashed")
        XCTAssertNotEqual(pairing.code, code, "a used code is replaced")
    }

    func testReplacesTheCodeAfterTooManyWrongTries() {
        var pairing = RemotePairing()
        let code = pairing.code
        let wrong = code == "000000" ? "111111" : "000000"
        for _ in 1..<RemotePairing.maximumAttempts {
            XCTAssertEqual(pairing.pair(with: wrong), .wrongCode)
        }
        XCTAssertEqual(pairing.pair(with: wrong), .codeReplaced)
        // The old code no longer works (unless the new one happens to match it).
        if pairing.code != code {
            XCTAssertEqual(pairing.pair(with: code), .wrongCode)
        }
    }

    func testForgettingKeys() {
        var pairing = RemotePairing()
        let code = pairing.code
        guard case .paired(let key) = pairing.pair(with: code) else { return XCTFail("didn't pair") }
        pairing.forgetAllKeys()
        XCTAssertFalse(pairing.accepts(key: key))
    }

    func testKeyFromHeaderOrQuery() {
        func request(headers: [String: String] = [:], query: [String: String] = [:]) -> HTTPRequest {
            HTTPRequest(method: "GET", pathComponents: [], query: query, headers: headers, body: Data())
        }
        XCTAssertEqual(RemotePairing.key(in: request(headers: ["authorization": "Bearer abc"])), "abc")
        XCTAssertEqual(RemotePairing.key(in: request(headers: ["x-switchboard-key": "def"])), "def")
        XCTAssertEqual(RemotePairing.key(in: request(query: ["key": "ghi"])), "ghi")
        XCTAssertNil(RemotePairing.key(in: request()))
    }
}
