import XCTest
@testable import Switchboard

/// DDC/CI wire format: Set/Get VCP Feature messages and reply parsing.
final class DDCPacketTests: XCTestCase {
    func testSetVCPBody() {
        XCTAssertEqual(DDCPacket.setVCPBody(VCP.brightness, value: 50), [0x84, 0x03, 0x10, 0x00, 0x32])
        XCTAssertEqual(DDCPacket.setVCPBody(VCP.brightness, value: 0x1234), [0x84, 0x03, 0x10, 0x12, 0x34])
    }

    func testGetVCPBody() {
        XCTAssertEqual(DDCPacket.getVCPBody(VCP.contrast), [0x82, 0x01, 0x12])
    }

    func testStandardChecksum() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        XCTAssertEqual(DDCPacket.withChecksum(DDCPacket.setVCPBody(VCP.brightness, value: 50)),
                       [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
    }

    func testPowerStandbyPacket() {
        // Standby (0xD6 = 0x05): 0x3F ^ 0x84 ^ 0x03 ^ 0xD6 ^ 0x00 ^ 0x05 = 0x6B
        let body = DDCPacket.setVCPBody(VCP.powerMode, value: UInt16(DisplayPower.standby.rawValue))
        XCTAssertEqual(DDCPacket.withChecksum(body), [0x84, 0x03, 0xD6, 0x00, 0x05, 0x6B])
    }

    func testCustomSeedChecksum() {
        // Read requests on Apple Silicon are seeded with 0x6E alone.
        // 0x6E ^ 0x82 ^ 0x01 ^ 0x10 = 0xFD
        XCTAssertEqual(DDCPacket.withChecksum(DDCPacket.getVCPBody(VCP.brightness), seed: 0x6E),
                       [0x82, 0x01, 0x10, 0xFD])
    }

    /// A valid reply: brightness 50 of 100. Checksum 0x50 ^ bytes 0...9 = 0xF2.
    private let validReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0xF2]

    func testParseValidReply() {
        XCTAssertEqual(DDCPacket.parseReply(validReply, vcp: VCP.brightness), VCPValue(current: 50, max: 100))
    }

    func testRejectsBadChecksum() {
        var reply = validReply
        reply[10] ^= 0xFF
        XCTAssertNil(DDCPacket.parseReply(reply, vcp: VCP.brightness))
    }

    func testRejectsOtherFeature() {
        XCTAssertNil(DDCPacket.parseReply(validReply, vcp: VCP.contrast))
    }

    func testRejectsUnsupportedResult() {
        var reply = validReply
        reply[3] = 0x01 // "unsupported VCP code"
        reply[10] ^= 0x01
        XCTAssertNil(DDCPacket.parseReply(reply, vcp: VCP.brightness))
    }

    func testRejectsShortReply() {
        XCTAssertNil(DDCPacket.parseReply(Array(validReply.prefix(8)), vcp: VCP.brightness))
    }

    func testRejectsZeroMaximum() {
        var reply = validReply
        reply[7] = 0x00 // max 0
        reply[10] ^= 0x64
        XCTAssertNil(DDCPacket.parseReply(reply, vcp: VCP.brightness))
    }

    func testClampsCurrentToMaximum() {
        var reply = validReply
        reply[9] = 0x70 // current 112 > max 100
        reply[10] ^= 0x32 ^ 0x70
        XCTAssertEqual(DDCPacket.parseReply(reply, vcp: VCP.brightness), VCPValue(current: 100, max: 100))
    }
}
