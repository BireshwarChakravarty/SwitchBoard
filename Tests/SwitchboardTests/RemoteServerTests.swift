import XCTest
@testable import Switchboard

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
