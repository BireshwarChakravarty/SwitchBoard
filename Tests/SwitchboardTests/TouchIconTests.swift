import XCTest

/// The iPhone remote's Home Screen icon, which scripts/make-app.sh bundles.
final class TouchIconTests: XCTestCase {
    private let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/TouchIcon.png")

    /// iOS wants a 180 × 180 PNG without transparency: it masks the corners
    /// itself and fills transparent pixels with black.
    func testIsAnOpaque180PointPNG() throws {
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "PNG signature")

        // IHDR: width and height (big-endian) at bytes 16–23, colour type at 25.
        func uint32(at offset: Int) -> UInt32 {
            data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        XCTAssertEqual(uint32(at: 16), 180)
        XCTAssertEqual(uint32(at: 20), 180)
        XCTAssertEqual(data[25], 2, "truecolour without alpha")
    }
}
