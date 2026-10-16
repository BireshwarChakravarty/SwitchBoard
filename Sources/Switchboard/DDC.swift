import Foundation
import CoreGraphics

/// DDC/CI VCP feature codes we use (VESA MCCS).
enum VCP {
    static let brightness: UInt8 = 0x10
    static let contrast: UInt8 = 0x12
    static let volume: UInt8 = 0x62
    /// Power mode.
    static let powerMode: UInt8 = 0xD6
}

/// Values for the power-mode VCP feature.
///
/// We use `.standby` (0x05) for "off" rather than `.hardOff` (0x04): in standby
/// the monitor keeps listening on the DDC bus, so we can turn it back ON with a
/// later DDC command. After a hard-off (0x04) many monitors stop answering DDC
/// and can only be woken with the physical power button — which would make the
/// "on" toggle useless.
enum DisplayPower: UInt8 {
    case on      = 0x01
    case standby = 0x05 // "off" for our purposes
    case hardOff = 0x04 // intentionally not used by the toggle
}

/// A continuous VCP control's state, as reported by the monitor.
struct VCPValue: Hashable {
    var current: UInt16
    var max: UInt16
}

/// Everything a transport needs to find a monitor's DDC bus.
///
/// Captured on the main thread while the display is online, so it is still
/// usable after a monitor in standby drops off macOS's display list.
struct DisplayIdentity: Hashable {
    let id: CGDirectDisplayID
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String

    /// Stable key for remembering per-monitor settings.
    var key: String { String(format: "%04X-%04X-%08X", vendor, model, serial) }

    init(id: CGDirectDisplayID, name: String) {
        self.id = id
        self.vendor = CGDisplayVendorNumber(id)
        self.model = CGDisplayModelNumber(id)
        self.serial = CGDisplaySerialNumber(id)
        self.name = name
    }
}

/// Abstracts the per-architecture DDC transport so the UI never sees IOKit.
///
/// DDC is slow (tens of milliseconds per message), so callers use these from a
/// background serial queue, never from the main thread concurrently. That
/// serial queue is what makes sharing a controller across threads safe.
protocol DDCController: AnyObject, Sendable {
    /// Set a VCP feature. Returns true if the monitor acknowledged the write.
    func write(_ vcp: UInt8, value: UInt16, for display: DisplayIdentity) -> Bool

    /// Read a continuous VCP feature (current and maximum value), or nil if the
    /// monitor doesn't answer or doesn't support it.
    func read(_ vcp: UInt8, for display: DisplayIdentity) -> VCPValue?

    /// The monitor's product name as the transport sees it (from its EDID),
    /// for displays macOS doesn't name. Nil if unknown.
    func productName(for id: CGDirectDisplayID) -> String?
}

extension DDCController {
    @discardableResult
    func setPower(_ power: DisplayPower, for display: DisplayIdentity) -> Bool {
        write(VCP.powerMode, value: UInt16(power.rawValue), for: display)
    }
}

/// DDC/CI message bodies, checksums and reply parsing.
///
/// On the wire every message is: destination 0x6E, source 0x51, then a body
/// whose first byte is 0x80 | (body length - 1), then a checksum. The
/// transports add the address bytes; these helpers build body + checksum.
enum DDCPacket {
    /// "Set VCP Feature": 0x84, opcode 0x03, vcp, value high, value low.
    static func setVCPBody(_ vcp: UInt8, value: UInt16) -> [UInt8] {
        [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    /// "Get VCP Feature": 0x82, opcode 0x01, vcp.
    static func getVCPBody(_ vcp: UInt8) -> [UInt8] {
        [0x82, 0x01, vcp]
    }

    /// Append the XOR checksum. The standard seed is 0x6E ^ 0x51 (both
    /// addresses); see Arm64DDC for the read-request exception.
    static func withChecksum(_ body: [UInt8], seed: UInt8 = 0x6E ^ 0x51) -> [UInt8] {
        var checksum = seed
        for byte in body { checksum ^= byte }
        return body + [checksum]
    }

    /// Length of a "Get VCP Feature" reply.
    static let replyLength = 11

    /// Parse a "Get VCP Feature" reply:
    ///   0x6E, 0x88, 0x02 (reply opcode), result (0 = ok), vcp, type,
    ///   max hi, max lo, current hi, current lo, checksum (seed 0x50).
    static func parseReply(_ reply: [UInt8], vcp: UInt8) -> VCPValue? {
        guard reply.count >= replyLength,
              reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { return nil }
        var checksum: UInt8 = 0x50
        for byte in reply[0..<10] { checksum ^= byte }
        guard checksum == reply[10] else { return nil }
        let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard max > 0 else { return nil }
        return VCPValue(current: Swift.min(current, max), max: max)
    }
}

/// The DDC transport. This app targets Apple Silicon Macs only.
enum DDC {
    static func makeController() -> DDCController {
        Arm64DDC()
    }
}
