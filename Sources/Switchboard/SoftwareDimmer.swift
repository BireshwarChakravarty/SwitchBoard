import Foundation
import CoreGraphics

/// Dims a screen in software by scaling its gamma (transfer) table, for
/// monitors whose brightness can't be set over DDC/CI. Level 1 is normal and
/// level 0 is black. The backlight stays on, so it's dimming, not power saving.
///
/// macOS resets gamma tables when displays are reconfigured or wake, so call
/// `reapplyAll()` after those events. Quitting the app (or a crash) restores
/// the normal tables automatically: Quartz undoes an app's gamma changes when
/// the app exits.
@MainActor
final class SoftwareDimmer {
    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    /// Each display's table as it was before we first dimmed it.
    private var originals: [CGDirectDisplayID: GammaTable] = [:]
    private var levels: [CGDirectDisplayID: Double] = [:]
    private var blackedOut: Set<CGDirectDisplayID> = []

    func level(for id: CGDirectDisplayID) -> Double {
        levels[id] ?? 1
    }

    func setLevel(_ level: Double, for id: CGDirectDisplayID) {
        let level = min(max(level, 0), 1)
        // Already undimmed: nothing to write (keeps slider drags cheap).
        if level >= 0.999 && levels[id] == nil { return }
        if originals[id] == nil {
            originals[id] = Self.readTable(id) ?? Self.linearTable
        }
        if level >= 0.999 {
            levels[id] = nil
        } else {
            levels[id] = level
        }
        apply(id)
    }

    func reapplyAll() {
        for id in Set(levels.keys).union(blackedOut) { apply(id) }
    }

    func isBlackedOut(_ id: CGDirectDisplayID) -> Bool { blackedOut.contains(id) }

    /// Black out a screen (or bring it back), independently of its dimming level.
    func setBlackedOut(_ black: Bool, for id: CGDirectDisplayID) {
        if originals[id] == nil {
            originals[id] = Self.readTable(id) ?? Self.linearTable
        }
        if black { blackedOut.insert(id) } else { blackedOut.remove(id) }
        apply(id)
    }

    /// Whether a screen's gamma table is currently (nearly) all black. Used to
    /// check that blacking out one screen didn't also black out another
    /// (screens that share a gamma table in a hardware mirror set).
    static func looksBlack(_ id: CGDirectDisplayID) -> Bool {
        guard let table = readTable(id) else { return false }
        let brightest = max(table.red.max() ?? 0, table.green.max() ?? 0, table.blue.max() ?? 0)
        return brightest < 0.05
    }

    /// Undo all dimming.
    func restoreAll() {
        levels.removeAll()
        blackedOut.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    private func apply(_ id: CGDirectDisplayID) {
        guard let table = originals[id] else { return }
        let factor = blackedOut.contains(id) ? 0 : CGGammaValue(levels[id] ?? 1)
        let red = table.red.map { $0 * factor }
        let green = table.green.map { $0 * factor }
        let blue = table.blue.map { $0 * factor }
        let result = CGSetDisplayTransferByTable(id, UInt32(red.count), red, green, blue)
        if result != .success {
            Log.display.error("CGSetDisplayTransferByTable(\(id)) failed: \(result.rawValue)")
        }
    }

    private static func readTable(_ id: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success,
              count > 1 else { return nil }
        let n = Int(count)
        return GammaTable(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }

    private static let linearTable: GammaTable = {
        let ramp = (0..<256).map { CGGammaValue($0) / 255 }
        return GammaTable(red: ramp, green: ramp, blue: ramp)
    }()
}
