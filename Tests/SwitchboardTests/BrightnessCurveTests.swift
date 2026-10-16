import XCTest
@testable import Switchboard

/// Combined brightness: DDC backlight on top, software dimming below.
final class BrightnessCurveTests: XCTestCase {
    func testTopOfScaleIsFullHardwareNoDimming() {
        let (hardware, software) = BrightnessCurve.split(1)
        XCTAssertEqual(hardware, 1, accuracy: 1e-9)
        XCTAssertEqual(software, 1, accuracy: 1e-9)
    }

    func testFloorIsZeroHardwareNoDimming() {
        let (hardware, software) = BrightnessCurve.split(BrightnessCurve.hardwareFloor)
        XCTAssertEqual(hardware, 0, accuracy: 1e-9)
        XCTAssertEqual(software, 1, accuracy: 1e-9)
    }

    func testBottomIsMinimumSoftwareLevelNeverBlack() {
        let (hardware, software) = BrightnessCurve.split(0)
        XCTAssertEqual(hardware, 0, accuracy: 1e-9)
        XCTAssertEqual(software, BrightnessCurve.minimumSoftwareLevel, accuracy: 1e-9)
        XCTAssertGreaterThan(software, 0)
    }

    func testSplitAndCombineRoundTrip() {
        for step in 0...100 {
            let level = Double(step) / 100
            let (hardware, software) = BrightnessCurve.split(level)
            XCTAssertEqual(BrightnessCurve.combined(hardware: hardware, software: software), level,
                           accuracy: 1e-9, "level \(level)")
        }
    }

    func testSoftwareOnlyRoundTrip() {
        for step in 0...100 {
            let position = Double(step) / 100
            let level = BrightnessCurve.softwareLevel(forDimming: position)
            XCTAssertEqual(BrightnessCurve.dimming(forSoftwareLevel: level), position, accuracy: 1e-9)
        }
    }

    func testSplitClampsOutOfRange() {
        XCTAssertEqual(BrightnessCurve.split(1.5).hardware, 1, accuracy: 1e-9)
        XCTAssertEqual(BrightnessCurve.split(-1).software, BrightnessCurve.minimumSoftwareLevel, accuracy: 1e-9)
    }

    func testStepsOnSixteenStepGrid() {
        XCTAssertEqual(BrightnessCurve.step(0.5, up: true, fine: false), 9.0 / 16, accuracy: 1e-9)
        XCTAssertEqual(BrightnessCurve.step(0.5, up: false, fine: false), 7.0 / 16, accuracy: 1e-9)
        // Off-grid values snap to the grid first.
        XCTAssertEqual(BrightnessCurve.step(0.51, up: true, fine: false), 9.0 / 16, accuracy: 1e-9)
    }

    func testFineStepsOnSixtyFourStepGrid() {
        XCTAssertEqual(BrightnessCurve.step(0.5, up: true, fine: true), 33.0 / 64, accuracy: 1e-9)
    }

    func testStepsStopAtEnds() {
        XCTAssertEqual(BrightnessCurve.step(1, up: true, fine: false), 1, accuracy: 1e-9)
        XCTAssertEqual(BrightnessCurve.step(0, up: false, fine: false), 0, accuracy: 1e-9)
    }
}
