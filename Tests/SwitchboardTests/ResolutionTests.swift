import XCTest
@testable import Switchboard

final class ResolutionTests: XCTestCase {
    func testLabel() {
        XCTAssertEqual(Resolution(width: 2560, height: 1440, isHiDPI: true).label, "2560 × 1440")
    }
}
