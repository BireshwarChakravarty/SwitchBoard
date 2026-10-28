import CoreGraphics

/// A resolution a screen can be set to, in points (what System Settings
/// calls "Looks like").
struct Resolution: Hashable {
    let width: Int
    let height: Int
    let isHiDPI: Bool

    var label: String { "\(width) × \(height)" }
}

/// The scaled resolutions of a screen, as System Settings offers them.
enum DisplayModes {
    /// Modes with the same shape as the current one, one per size (HiDPI
    /// preferred, then the current refresh rate), smallest first, and the
    /// index of the current one.
    static func available(for id: CGDirectDisplayID) -> (modes: [CGDisplayMode], current: Int)? {
        guard let current = CGDisplayCopyDisplayMode(id), current.height > 0 else { return nil }
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return nil }

        let aspect = Double(current.width) / Double(current.height)
        var bySize: [String: CGDisplayMode] = [:]
        for mode in all where mode.isUsableForDesktopGUI() && mode.height > 0 {
            guard abs(Double(mode.width) / Double(mode.height) - aspect) < 0.02 else { continue }
            let key = "\(mode.width)x\(mode.height)"
            if let existing = bySize[key], !isPreferred(mode, over: existing, current: current) { continue }
            bySize[key] = mode
        }
        let modes = bySize.values.sorted { ($0.width, $0.height) < ($1.width, $1.height) }
        guard let index = modes.firstIndex(where: { $0.width == current.width && $0.height == current.height })
        else { return nil }
        return (modes, index)
    }

    /// The screen's refresh rate in whole hertz, if macOS reports one.
    static func refreshRate(of id: CGDirectDisplayID) -> Int? {
        guard let rate = CGDisplayCopyDisplayMode(id)?.refreshRate, rate > 0 else { return nil }
        return Int(rate.rounded())
    }

    static func resolution(of mode: CGDisplayMode) -> Resolution {
        Resolution(width: mode.width, height: mode.height, isHiDPI: mode.pixelWidth > mode.width)
    }

    /// Switch the screen to `mode`, kept across logins like a change made in
    /// System Settings.
    static func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, id, mode, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result != .success {
            Log.display.error("Changing resolution of display \(id) failed: \(result.rawValue)")
        }
        return result == .success
    }

    private static func isPreferred(_ a: CGDisplayMode, over b: CGDisplayMode, current: CGDisplayMode) -> Bool {
        let aHiDPI = a.pixelWidth > a.width
        let bHiDPI = b.pixelWidth > b.width
        if aHiDPI != bHiDPI { return aHiDPI }
        let aCurrentRate = a.refreshRate == current.refreshRate
        let bCurrentRate = b.refreshRate == current.refreshRate
        if aCurrentRate != bCurrentRate { return aCurrentRate }
        return a.refreshRate > b.refreshRate
    }
}
