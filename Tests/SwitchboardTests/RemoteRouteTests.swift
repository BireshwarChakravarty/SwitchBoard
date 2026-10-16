import XCTest
@testable import Switchboard

/// Which request means what.
final class RemoteRouteTests: XCTestCase {
    private func route(_ method: String, _ path: String) -> Result<RemoteRoute, RemoteRoute.Failure> {
        RemoteRoute.resolve(method: method, path: path.split(separator: "/").map(String.init))
    }

    func testPagesAndState() {
        XCTAssertEqual(route("GET", ""), .success(.page))
        XCTAssertEqual(route("GET", "manifest.webmanifest"), .success(.manifest))
        XCTAssertEqual(route("GET", "icon.png"), .success(.icon))
        XCTAssertEqual(route("GET", "apple-touch-icon.png"), .success(.icon))
        XCTAssertEqual(route("GET", "apple-touch-icon-precomposed.png"), .success(.icon))
        XCTAssertEqual(route("GET", "Switchboard.mobileconfig"), .success(.webClip))
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
        XCTAssertFalse(RemoteRoute.webClip.needsKey)
        XCTAssertTrue(RemoteRoute.state.needsKey)
        XCTAssertTrue(RemoteRoute.power(screen: "x", on: false).needsKey)
        XCTAssertTrue(RemoteRoute.set(screen: "x", control: .volume, value: 1).needsKey)
    }
}
