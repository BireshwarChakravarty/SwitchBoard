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
        XCTAssertTrue(text.contains("Content-Length: 33\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{\"error\":\"Nope\",\"message\":\"Nope\"}"))
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
        XCTAssertEqual(route("POST", "api/screens/all/brightness/40.6"),
                       .success(.set(screen: "all", control: .brightness, value: 41)))
        XCTAssertEqual(route("POST", "api/screens/all/brightness/40%"),
                       .success(.set(screen: "all", control: .brightness, value: 40)))
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

/// Ready-made Shortcuts for Siri.
final class RemoteShortcutsTests: XCTestCase {
    private let base = "http://Mac-mini.local:8723"
    private let key = String(repeating: "a", count: 64)

    private func actions(_ workflow: [String: Any]) -> [[String: Any]] {
        workflow["WFWorkflowActions"] as? [[String: Any]] ?? []
    }

    private func parameters(_ action: [String: Any]) -> [String: Any] {
        action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]
    }

    func testMakesPowerAndBrightnessShortcuts() {
        let shortcuts = RemoteShortcuts.make(base: base, key: key,
                                             switchable: [(name: "ARZOPA", slug: "arzopa")], brightness: true)
        XCTAssertEqual(shortcuts.map(\.name), ["ARZOPA On", "ARZOPA Off", "Toggle ARZOPA", "Screen Brightness"])

        let off = actions(shortcuts[1].workflow)
        XCTAssertEqual(off.map { $0["WFWorkflowActionIdentifier"] as? String },
                       ["is.workflow.actions.downloadurl", "is.workflow.actions.getvalueforkey",
                        "is.workflow.actions.showresult"])
        XCTAssertEqual(parameters(off[0])["WFURL"] as? String, "\(base)/api/screens/arzopa/off?key=\(key)")
        XCTAssertEqual(parameters(off[0])["WFHTTPMethod"] as? String, "POST")
        XCTAssertEqual(parameters(off[1])["WFDictionaryKey"] as? String, "message")
    }

    func testOutputsAreWiredByUUID() {
        let workflow = RemoteShortcuts.askingRequest(prompt: "?", urlBefore: "\(base)/x/", urlAfter: "?key=k")
        let steps = actions(workflow)
        XCTAssertEqual(steps.map { $0["WFWorkflowActionIdentifier"] as? String },
                       ["is.workflow.actions.ask", "is.workflow.actions.downloadurl",
                        "is.workflow.actions.getvalueforkey", "is.workflow.actions.showresult"])
        let askUUID = parameters(steps[0])["UUID"] as? String
        let fetchUUID = parameters(steps[1])["UUID"] as? String
        XCTAssertNotNil(askUUID)

        // The URL holds the answer where U+FFFC is.
        let url = (parameters(steps[1])["WFURL"] as? [String: Any])?["Value"] as? [String: Any]
        let string = url?["string"] as? String
        XCTAssertEqual(string, "\(base)/x/\u{FFFC}?key=k")
        let ranges = url?["attachmentsByRange"] as? [String: [String: Any]]
        let position = "\(base)/x/".utf16.count
        XCTAssertEqual(ranges?["{\(position), 1}"]?["OutputUUID"] as? String, askUUID)
        XCTAssertEqual(ranges?["{\(position), 1}"]?["OutputName"] as? String, "Provided Input")

        // The message is read from the URL's reply.
        let input = (parameters(steps[2])["WFInput"] as? [String: Any])?["Value"] as? [String: Any]
        XCTAssertEqual(input?["OutputUUID"] as? String, fetchUUID)
        XCTAssertEqual(input?["OutputName"] as? String, "Contents of URL")
    }

    func testSerializesAsPropertyList() throws {
        let shortcut = RemoteShortcuts.make(base: base, key: key, switchable: [], brightness: true)[0]
        let data = try RemoteShortcuts.data(for: shortcut)
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual((back?["WFWorkflowActions"] as? [Any])?.count, 4)
    }

    func testFileNames() {
        XCTAssertEqual(RemoteShortcuts.fileName(for: "Toggle ARZOPA"), "Toggle ARZOPA.shortcut")
        XCTAssertEqual(RemoteShortcuts.fileName(for: "A/B: C"), "A-B- C.shortcut")
    }

    /// Signs a shortcut with Apple's tool where it can (it needs a signed-in
    /// Apple Account, which CI machines may not have), to catch files the
    /// tool rejects.
    func testSigningWhereAvailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shortcut = RemoteShortcuts.make(base: base, key: key,
                                            switchable: [(name: "ARZOPA", slug: "arzopa")], brightness: true)[3]
        let input = folder.appendingPathComponent("in.shortcut")
        try RemoteShortcuts.data(for: shortcut).write(to: input)
        let output = folder.appendingPathComponent("out.shortcut")
        switch ShortcutSigner.sign(input, to: output) {
        case .success:
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
            print("Shortcut signing: OK (\(size) bytes)")
            XCTAssertGreaterThan(size, 0)
        case .failure(let failure):
            throw XCTSkip("Shortcut signing unavailable here: \(failure.message)")
        }
    }
}
