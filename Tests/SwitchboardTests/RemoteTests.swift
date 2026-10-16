import XCTest
@testable import Switchboard

/// HTTP parsing for the iPhone remote.
final class RemoteHTTPTests: XCTestCase {
    private func parse(_ text: String) -> HTTPParseResult {
        HTTPParser.parse(Data(text.utf8))
    }

    func testParsesPathQueryAndHeaders() {
        guard case .complete(let request) = parse(
            "GET /api/screens/XV272K%20V5/brightness/40?key=abc HTTP/1.1\r\nHost: mac.local\r\nX-Switchboard-Key: k\r\n\r\n"
        ) else { return XCTFail("not parsed") }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.pathComponents, ["api", "screens", "XV272K V5", "brightness", "40"])
        XCTAssertEqual(request.query["key"], "abc")
        XCTAssertEqual(request.headers["x-switchboard-key"], "k")
        XCTAssertEqual(request.headers["host"], "mac.local")
    }

    func testWaitsForHeadersAndBody() {
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nHost: x\r\n"), .incomplete)
        XCTAssertEqual(parse("POST /api/pair HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"co"), .incomplete)
    }

    func testReadsBody() {
        guard case .complete(let request) = parse(
            "POST /api/pair HTTP/1.1\r\nContent-Length: 17\r\n\r\n{\"code\":\"123456\"}"
        ) else { return XCTFail("not parsed") }
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "{\"code\":\"123456\"}")
    }

    func testRejectsMalformedAndOversized() {
        XCTAssertEqual(parse("nonsense\r\n\r\n"), .invalid)
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nBroken header\r\n\r\n"), .invalid)
        XCTAssertEqual(parse("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"), .invalid)
        XCTAssertEqual(parse("GET http://elsewhere/ HTTP/1.1\r\n\r\n"), .invalid)
        let huge = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPParser.maximumSize) + "\r\n\r\n"
        XCTAssertEqual(parse(huge), .invalid)
    }

    func testSerializesResponse() {
        let text = String(decoding: HTTPResponse.error("Nope", status: 404).serialized, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 16\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{\"error\":\"Nope\"}"))
    }
}

/// Which request means what.
final class RemoteRouteTests: XCTestCase {
    private func route(_ method: String, _ path: String) -> Result<RemoteRoute, RemoteRoute.Failure> {
        RemoteRoute.resolve(method: method, path: path.split(separator: "/").map(String.init))
    }

    func testPagesAndState() {
        XCTAssertEqual(route("GET", ""), .success(.page))
        XCTAssertEqual(route("GET", "manifest.webmanifest"), .success(.manifest))
        XCTAssertEqual(route("GET", "icon.png"), .success(.icon))
        XCTAssertEqual(route("GET", "api/screens"), .success(.state))
        XCTAssertEqual(route("POST", "api/pair"), .success(.pair))
    }

    func testPower() {
        XCTAssertEqual(route("POST", "api/screens/arzopa/off"), .success(.power(screen: "arzopa", on: false)))
        XCTAssertEqual(route("POST", "api/screens/arzopa/ON"), .success(.power(screen: "arzopa", on: true)))
        XCTAssertEqual(route("POST", "api/screens/arzopa/toggle"), .success(.power(screen: "arzopa", on: nil)))
        XCTAssertEqual(route("POST", "api/screens/arzopa/explode"), .failure(.notFound))
    }

    func testControls() {
        XCTAssertEqual(route("POST", "api/screens/acer/brightness/40"),
                       .success(.set(screen: "acer", control: .brightness, value: 40)))
        XCTAssertEqual(route("POST", "api/screens/all/brightness/0"),
                       .success(.set(screen: "all", control: .brightness, value: 0)))
        XCTAssertEqual(route("POST", "api/screens/acer/resolution/3"),
                       .success(.set(screen: "acer", control: .resolution, value: 3)))
        XCTAssertEqual(route("POST", "api/screens/acer/contrast/101"), .failure(.badValue("Use a value from 0 to 100")))
        XCTAssertEqual(route("POST", "api/screens/acer/volume/loud"), .failure(.badValue("loud isn't a number")))
        XCTAssertEqual(route("POST", "api/screens/acer/sharpness/5"), .failure(.notFound))
    }

    func testActionsNeedPostAndReadsNeedGet() {
        XCTAssertEqual(route("GET", "api/screens/arzopa/off"), .failure(.methodNotAllowed))
        XCTAssertEqual(route("POST", "api/screens"), .failure(.methodNotAllowed))
        XCTAssertEqual(route("GET", "api/pair"), .failure(.methodNotAllowed))
    }

    func testOnlyPageAndPairingAreOpen() {
        XCTAssertFalse(RemoteRoute.page.needsKey)
        XCTAssertFalse(RemoteRoute.pair.needsKey)
        XCTAssertTrue(RemoteRoute.state.needsKey)
        XCTAssertTrue(RemoteRoute.power(screen: "x", on: false).needsKey)
        XCTAssertTrue(RemoteRoute.set(screen: "x", control: .volume, value: 1).needsKey)
    }
}

/// Finding the screen a shortcut names.
final class RemoteScreenMatcherTests: XCTestCase {
    private let screens: [(id: UInt32, name: String)] = [
        (id: 2, name: "XV272K V5"),
        (id: 3, name: "ARZOPA"),
        (id: 4, name: "DELL U2723QE"),
        (id: 5, name: "DELL P2422H")
    ]

    func testMatchesNamesLoosely() {
        XCTAssertEqual(RemoteScreenMatcher.match("ARZOPA", in: screens), 3)
        XCTAssertEqual(RemoteScreenMatcher.match("arzopa", in: screens), 3)
        XCTAssertEqual(RemoteScreenMatcher.match("xv272k-v5", in: screens), 2)
        XCTAssertEqual(RemoteScreenMatcher.match("xv272k", in: screens), 2)
        XCTAssertEqual(RemoteScreenMatcher.match("u2723", in: screens), 4)
        XCTAssertEqual(RemoteScreenMatcher.match("3", in: screens), 3)
    }

    func testAmbiguousOrUnknownMatchesNothing() {
        XCTAssertNil(RemoteScreenMatcher.match("dell", in: screens))
        XCTAssertNil(RemoteScreenMatcher.match("lg", in: screens))
        XCTAssertNil(RemoteScreenMatcher.match("--", in: screens))
        XCTAssertNil(RemoteScreenMatcher.match("99", in: screens))
    }

    func testSlug() {
        XCTAssertEqual(RemoteScreenMatcher.slug("XV272K V5"), "xv272k-v5")
        XCTAssertEqual(RemoteScreenMatcher.slug("ARZOPA"), "arzopa")
        XCTAssertEqual(RemoteScreenMatcher.slug("???"), "screen")
    }
}

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

/// The server answering real requests over the network.
final class RemoteServerTests: XCTestCase {
    func testServesRequests() async throws {
        let server = RemoteServer { request in
            if request.pathComponents == ["echo"] {
                return HTTPResponse(status: 200, contentType: "text/plain", body: Data((request.query["say"] ?? "").utf8))
            }
            return .error("Not found", status: 404)
        }
        let port: UInt16 = 18_723
        let ready = expectation(description: "listening")
        server.start(port: port) { result in
            if case .success = result { ready.fulfill() }
        }
        await fulfillment(of: [ready], timeout: 10)
        defer { server.stop() }

        let (body, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/echo?say=hello")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "hello")

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/missing")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }
}
