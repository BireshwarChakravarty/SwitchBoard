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
        XCTAssertTrue(text.contains("Cache-Control: no-store\r\n"))
    }

    /// HEAD gets the GET reply's headers, including its real length, and no body.
    func testHeadKeepsContentLength() {
        var response = HTTPResponse(status: 200, contentType: "image/png", body: Data(count: 24),
                                    cacheControl: "public, max-age=86400")
        response.omitsBody = true
        let text = String(decoding: response.serialized, as: UTF8.self)
        XCTAssertTrue(text.contains("Content-Length: 24\r\n"))
        XCTAssertTrue(text.contains("Cache-Control: public, max-age=86400\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"))
    }
}
