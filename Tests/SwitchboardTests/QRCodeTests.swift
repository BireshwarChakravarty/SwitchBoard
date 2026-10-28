import XCTest
@testable import Switchboard

/// The QR code Settings shows for the iPhone Remote's address.
final class QRCodeTests: XCTestCase {
    func testMakesASquareImageScaledPerModule() throws {
        let image = try XCTUnwrap(QRCode.image(for: "http://Mac-mini.local:8723", scale: 4))
        XCTAssertEqual(image.size.width, image.size.height)
        // A version 2 code or larger is at least 25 modules wide.
        XCTAssertGreaterThanOrEqual(image.size.width, 25 * 4)
        XCTAssertEqual(image.size.width.truncatingRemainder(dividingBy: 4), 0)
    }
}
