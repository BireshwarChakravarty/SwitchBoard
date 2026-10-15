import Foundation
import IOKit
import CoreGraphics

/// Apple-Silicon DDC transport.
///
/// On Apple Silicon there is no public CGDisplayID → I2C bus mapping. The
/// working approach (shared by m1ddc and MonitorControl) is:
///   1. Walk the whole IOService plane in order.
///   2. Each framebuffer node (`AppleCLCD2` / `IOMobileFramebufferShim`)
///      carries the attached monitor's `EDID UUID` and `DisplayAttributes`.
///      Its DDC port is the next `DCPAVServiceProxy` node in the walk — a
///      sibling branch, not an ancestor — so pair each proxy with the
///      framebuffer seen just before it.
///   3. Keep only proxies whose `Location` is `External` (the built-in panel
///      has an `Embedded` one), and create an `IOAVService` from each.
///   4. Score every candidate against the CGDisplayID's vendor/model/serial
///      and name, and use the best one.
///
/// If a toggle hits the wrong screen (or none), run the app from Terminal with
/// `swift run`: the candidates and their scores are logged there.
final class Arm64DDC: DDCController {

    private struct FramebufferInfo {
        var edidUUID = ""
        var productName: String?
        var vendor: UInt32?
        var model: UInt32?
        var serial: UInt32?
    }

    private struct AVCandidate {
        let service: IOAVService
        let info: FramebufferInfo
    }

    /// The DDC service that last worked for each display. A monitor in standby
    /// can vanish from the IORegistry's display data, so waking it relies on
    /// the handle we used to put it to sleep.
    private var cache: [CGDirectDisplayID: IOAVService] = [:]

    func write(_ vcp: UInt8, value: UInt16, for display: DisplayIdentity) -> Bool {
        let packet = DDCPacket.withChecksum(DDCPacket.setVCPBody(vcp, value: value))

        if let cached = cache[display.id] {
            if send(packet, to: cached) { return true }
            cache[display.id] = nil // stale handle: look the display up again
        }
        guard let service = findService(for: display) else {
            Log.ddc.error("No DDC service matched \(display.name, privacy: .public) (display \(display.id))")
            return false
        }
        guard send(packet, to: service) else { return false }
        cache[display.id] = service
        return true
    }

    func read(_ vcp: UInt8, for display: DisplayIdentity) -> VCPValue? {
        guard let service = cache[display.id] ?? findService(for: display) else { return nil }
        let body = DDCPacket.getVCPBody(vcp)
        // m1ddc and MonitorControl seed a read request's checksum with 0x6E
        // alone on Apple Silicon; fall back to the standard seed if that
        // gets no valid reply.
        for seed: UInt8 in [0x6E, 0x6E ^ 0x51] {
            let request = DDCPacket.withChecksum(body, seed: seed)
            for _ in 0..<2 {
                guard send(request, to: service) else { continue }
                usleep(50_000) // monitors need time to prepare the reply
                var reply = [UInt8](repeating: 0, count: DDCPacket.replyLength)
                let result = reply.withUnsafeMutableBytes { raw -> IOReturn in
                    IOAVServiceReadI2C(service, 0x37, 0x51, raw.baseAddress!, UInt32(raw.count))
                }
                if result == KERN_SUCCESS, let value = DDCPacket.parseReply(reply, vcp: vcp) {
                    cache[display.id] = service
                    return value
                }
                usleep(20_000)
            }
        }
        Log.ddc.notice("No reply reading VCP \(String(format: "0x%02X", vcp), privacy: .public) from \(display.name, privacy: .public)")
        return nil
    }

    // MARK: I2C write (chip 0x37, source offset 0x51)

    private func send(_ bytes: [UInt8], to service: IOAVService) -> Bool {
        // A couple of retries: DDC is a lossy, best-effort bus.
        for attempt in 0..<3 {
            usleep(10_000)
            let result = bytes.withUnsafeBytes { raw -> IOReturn in
                IOAVServiceWriteI2C(service, 0x37, 0x51, raw.baseAddress!, UInt32(bytes.count))
            }
            if result == KERN_SUCCESS { return true }
            Log.ddc.debug("IOAVServiceWriteI2C attempt \(attempt) failed: \(result)")
        }
        return false
    }

    func productName(for id: CGDirectDisplayID) -> String? {
        let display = DisplayIdentity(id: id, name: "")
        let best = collectCandidates()
            .map { ($0.info, score($0.info, against: display)) }
            .max(by: { $0.1 < $1.1 })
        guard let best, best.1 > 0, let name = best.0.productName, !name.isEmpty else { return nil }
        return name
    }

    // MARK: DisplayIdentity → IOAVService

    private func findService(for display: DisplayIdentity) -> IOAVService? {
        let candidates = collectCandidates()
        let scored = candidates.map { ($0, score($0.info, against: display)) }

        Log.ddc.info("Matching \(display.name, privacy: .public): vendor \(String(format: "%04X", display.vendor), privacy: .public) model \(String(format: "%04X", display.model), privacy: .public) serial \(display.serial)")
        for (candidate, score) in scored {
            let info = candidate.info
            Log.ddc.info("  candidate \(info.productName ?? "?", privacy: .public), EDID UUID \(info.edidUUID, privacy: .public), score \(score)")
        }

        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 {
            if scored.filter({ $0.1 == best.1 }).count > 1 {
                Log.ddc.notice("Several DDC services match equally; using the first")
            }
            return best.0.service
        }
        // Nothing identifiable, but only one external port: it must be this one.
        if candidates.count == 1 { return candidates[0].service }
        return nil
    }

    private func score(_ info: FramebufferInfo, against display: DisplayIdentity) -> Int {
        var score = 0
        // "EDID UUID" starts with the EDID vendor ID (big-endian hex) and the
        // product code (little-endian hex): a Dell (0x10AC) model 0xA0D3 reads
        // "10ACD3A0-...".
        let uuid = info.edidUUID.uppercased()
        if uuid.count >= 8 {
            let vendorHex = String(format: "%04X", display.vendor & 0xFFFF)
            let modelHex = String(format: "%02X%02X", display.model & 0xFF, (display.model >> 8) & 0xFF)
            if uuid.prefix(4) == vendorHex { score += 1 }
            if uuid.dropFirst(4).prefix(4) == modelHex { score += 1 }
        }
        if let vendor = info.vendor, vendor == display.vendor { score += 1 }
        if let model = info.model, model == display.model { score += 1 }
        // The serial is what tells two identical monitors apart.
        if display.serial != 0, let serial = info.serial, serial == display.serial { score += 2 }
        if let name = info.productName, !name.isEmpty, name == display.name { score += 1 }
        return score
    }

    /// Walk the IOService plane collecting external DDC services, each paired
    /// with the framebuffer (and so the monitor) that precedes it.
    private func collectCandidates() -> [AVCandidate] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        let nameBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer { nameBuffer.deallocate() }

        var candidates: [AVCandidate] = []
        var lastFramebuffer: FramebufferInfo?
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                lastFramebuffer = framebufferInfo(entry)
            } else if name.contains("DCPAVServiceProxy") {
                guard copyProperty("Location", of: entry) as? String == "External",
                      let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)
                else { continue }
                candidates.append(AVCandidate(service: service, info: lastFramebuffer ?? FramebufferInfo()))
                lastFramebuffer = nil
            }
        }
        return candidates
    }

    private func framebufferInfo(_ entry: io_registry_entry_t) -> FramebufferInfo {
        var info = FramebufferInfo()
        info.edidUUID = copyProperty("EDID UUID", of: entry) as? String ?? ""
        if let attrs = copyProperty("DisplayAttributes", of: entry) as? [String: Any],
           let product = attrs["ProductAttributes"] as? [String: Any] {
            info.productName = product["ProductName"] as? String
            info.vendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value
            info.model = (product["ProductID"] as? NSNumber)?.uint32Value
            info.serial = (product["SerialNumber"] as? NSNumber)?.uint32Value
        }
        return info
    }

    private func copyProperty(_ key: String, of entry: io_registry_entry_t) -> Any? {
        guard let ref = IORegistryEntryCreateCFProperty(
            entry, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return ref.takeRetainedValue()
    }
}
