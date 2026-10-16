import XCTest
@testable import Switchboard

/// Judging whether a monitor acted on a factory-reset command.
final class FactoryRestoreTests: XCTestCase {
    private let dimmed: [UInt8: VCPValue] = [
        VCP.brightness: VCPValue(current: 30, max: 100),
        VCP.contrast: VCPValue(current: 35, max: 100)
    ]
    private let factory: [UInt8: VCPValue] = [
        VCP.brightness: VCPValue(current: 80, max: 100),
        VCP.contrast: VCPValue(current: 50, max: 100)
    ]

    func testUnreachableWhenNotSent() {
        XCTAssertEqual(FactoryRestoreOutcome.evaluate(sent: false, before: dimmed, after: factory), .unreachable)
        XCTAssertTrue(FactoryRestoreOutcome.unreachable.message.isProblem)
    }

    func testUnconfirmedWhenNothingReadBack() {
        XCTAssertEqual(FactoryRestoreOutcome.evaluate(sent: true, before: dimmed, after: [:]), .unconfirmed)
        XCTAssertFalse(FactoryRestoreOutcome.unconfirmed.message.isProblem)
    }

    func testRestoredWhenValuesChange() {
        let outcome = FactoryRestoreOutcome.evaluate(sent: true, before: dimmed, after: factory)
        XCTAssertEqual(outcome, .restored(summary: "Brightness 80% · Contrast 50%"))
        XCTAssertEqual(outcome.message.text, "Restored · Brightness 80% · Contrast 50%")
        XCTAssertFalse(outcome.message.isProblem)
    }

    func testIgnoredWhenValuesDontChange() {
        let outcome = FactoryRestoreOutcome.evaluate(sent: true, before: dimmed, after: dimmed)
        XCTAssertEqual(outcome, .ignored(summary: "Brightness 30% · Contrast 35%"))
        XCTAssertEqual(outcome.message.text, "Monitor ignored it · Brightness 30% · Contrast 35%")
        XCTAssertTrue(outcome.message.isProblem)
    }

    func testReadBackWhenNothingToCompare() {
        let outcome = FactoryRestoreOutcome.evaluate(sent: true, before: [:], after: factory)
        XCTAssertEqual(outcome.message.text, "Reset sent · now Brightness 80% · Contrast 50%")
    }

    func testSummaryUsesPercentOfMaximum() {
        let values: [UInt8: VCPValue] = [VCP.contrast: VCPValue(current: 64, max: 128)]
        XCTAssertEqual(FactoryRestoreOutcome.summary(of: values), "Contrast 50%")
    }
}
