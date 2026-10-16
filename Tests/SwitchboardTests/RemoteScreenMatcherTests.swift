import XCTest
@testable import Switchboard

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
