import XCTest
@testable import Switchboard

/// Which keyboard HID usages count as brightness keys.
final class KeyboardReaderTests: XCTestCase {
    private func key(_ page: Int, _ usage: Int, fn: Bool = false, standard: Bool = false) -> MediaKey? {
        KeyboardReader.brightnessKey(page: page, usage: usage, fnHeld: fn, standardFunctionKeys: standard)
    }

    func testConsumerBrightnessUsages() {
        XCTAssertEqual(key(0x0C, 0x6F), .brightnessUp)
        XCTAssertEqual(key(0x0C, 0x70), .brightnessDown)
    }

    func testAppleTopCaseUsages() {
        XCTAssertEqual(key(0xFF, 0x04), .brightnessUp)
        XCTAssertEqual(key(0xFF, 0x05), .brightnessDown)
    }

    func testF14AndF15() {
        XCTAssertEqual(key(0x07, 0x69), .brightnessDown)
        XCTAssertEqual(key(0x07, 0x6A), .brightnessUp)
    }

    func testF1F2AreBrightnessByDefault() {
        XCTAssertEqual(key(0x07, 0x3A), .brightnessDown)
        XCTAssertEqual(key(0x07, 0x3B), .brightnessUp)
    }

    func testFnMakesF1F2FunctionKeys() {
        XCTAssertNil(key(0x07, 0x3A, fn: true))
        XCTAssertNil(key(0x07, 0x3B, fn: true))
    }

    func testStandardFunctionKeysSettingFlipsF1F2() {
        XCTAssertNil(key(0x07, 0x3A, standard: true))
        XCTAssertEqual(key(0x07, 0x3A, fn: true, standard: true), .brightnessDown)
    }

    func testOtherKeysAreIgnored() {
        XCTAssertNil(key(0x07, 0x04))   // "a"
        XCTAssertNil(key(0x07, 0x3C))   // F3
        XCTAssertNil(key(0x0C, 0xE9))   // volume up (handled elsewhere)
    }
}
