import XCTest
@testable import Switchboard

/// Which screens Switchboard only switches on and off.
final class ManagedDisplayTests: XCTestCase {
    private func display(builtIn: Bool = false, offMethod: OffMethod, softwareDimming: Bool = false) -> ManagedDisplay {
        var display = ManagedDisplay(id: 2, name: "Portable", isBuiltIn: builtIn, isMain: false, isOn: true)
        display.offMethod = offMethod
        display.softwareDimming = softwareDimming
        return display
    }

    func testMonitorWithoutDDCIsPowerOnlyByDefault() {
        XCTAssertTrue(display(offMethod: .disconnect).isPowerOnly)
    }

    func testSoftwareDimmingGivesItBrightnessControl() {
        XCTAssertFalse(display(offMethod: .disconnect, softwareDimming: true).isPowerOnly)
    }

    func testDDCMonitorsAndBuiltInScreensAreNotPowerOnly() {
        XCTAssertFalse(display(offMethod: .standby).isPowerOnly)
        XCTAssertFalse(display(builtIn: true, offMethod: .disconnect).isPowerOnly)
    }
}
