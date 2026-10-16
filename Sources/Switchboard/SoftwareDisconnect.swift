import Foundation
import CoreGraphics

/// Switches a display off "in software": macOS stops using it as if the cable
/// had been pulled, so windows move to the remaining screens and the monitor
/// sees no signal (most then go to sleep on their own). It tries to keep the
/// other screens on by disabling the default fade-to-black of display
/// configurations.
///
/// This is the fallback for monitors that don't answer DDC/CI. It uses the
/// private `CGSConfigureDisplayEnabled`, looked up at runtime so the app still
/// builds and runs if a macOS release removes it. The change is made for this
/// login session only: logging out (or the app reconnecting on quit/relaunch)
/// brings the display back.
enum SoftwareDisconnect {
    private typealias ConfigureEnabled =
        @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> Int32

    private static let configureEnabled: ConfigureEnabled? = {
        let libraries = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        ]
        for path in libraries {
            if let handle = dlopen(path, RTLD_NOW),
               let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") {
                return unsafeBitCast(symbol, to: ConfigureEnabled.self)
            }
        }
        Log.display.error("CGSConfigureDisplayEnabled not found; software disconnect unavailable")
        return nil
    }()

    /// Ways to disconnect a screen while trying to keep the others on. macOS
    /// rejects a configuration without its fade (kCGErrorNotImplemented), so
    /// these work around the blank instead. Chosen in a screen's right-click
    /// menu (Disconnect Style) while we find the one that works best.
    enum Style: String, CaseIterable, Hashable {
        /// A plain configuration: macOS fades/reconfigures every screen.
        case standard
        /// Also re-apply every other screen's current mode in the same
        /// configuration, so macOS has no reason to change them.
        case keepModes
        /// Take the screen out of its mirror set in the same configuration
        /// (and put it back on reconnect), so the mirror isn't torn down
        /// separately.
        case unmirrorFirst
        /// Hold a fade reservation while the configuration completes, which
        /// can stop macOS running its own fade.
        case holdFade
        /// Apply the change for this app only (macOS undoes it when the app
        /// quits) rather than for the login session, which makes macOS save
        /// and reload the whole display setup.
        case appOnly
        /// Apply the change permanently (as System Settings would).
        case permanent

        /// How long the change lasts.
        var option: CGConfigureOption {
            switch self {
            case .appOnly: .forAppOnly
            case .permanent: .permanently
            default: .forSession
            }
        }

        var title: String {
            switch self {
            case .standard: "Standard"
            case .keepModes: "Keep Other Screens' Modes"
            case .unmirrorFirst: "Unmirror First"
            case .holdFade: "Hold Fade"
            case .appOnly: "App Only"
            case .permanent: "Permanent"
            }
        }
    }

    /// The screen each disconnected screen mirrored, to restore on reconnect.
    private static var mirrorSources: [CGDirectDisplayID: CGDirectDisplayID] = [:]

    /// Enable (reconnect) or disable (disconnect) a display. Returns true on
    /// success. If the chosen style is rejected, falls back to `.standard`.
    @discardableResult
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID, style: Style = .standard) -> Bool {
        if apply(enabled, displayID: displayID, style: style) { return true }
        guard style != .standard else { return false }
        Log.display.notice("Display \(displayID): \(style.rawValue, privacy: .public) rejected, retrying standard")
        return apply(enabled, displayID: displayID, style: .standard)
    }

    private static func apply(_ enabled: Bool, displayID: CGDirectDisplayID, style: Style) -> Bool {
        guard let configure = configureEnabled else { return false }

        var config: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&config)
        guard begun == .success, let config else {
            Log.display.error("CGBeginDisplayConfiguration failed: \(begun.rawValue)")
            return false
        }

        let others = Displays.active().filter { $0 != displayID }
        switch style {
        case .standard, .holdFade, .appOnly, .permanent:
            break
        case .keepModes:
            for other in others {
                guard let mode = CGDisplayCopyDisplayMode(other) else { continue }
                let kept = CGConfigureDisplayWithDisplayMode(config, other, mode, nil)
                if kept != .success {
                    Log.display.notice("Keeping mode of display \(other) failed: \(kept.rawValue)")
                }
            }
        case .unmirrorFirst:
            if enabled {
                if let source = mirrorSources.removeValue(forKey: displayID) {
                    let mirrored = CGConfigureDisplayMirrorOfDisplay(config, displayID, source)
                    if mirrored != .success {
                        Log.display.notice("Re-mirroring display \(displayID) failed: \(mirrored.rawValue)")
                    }
                }
            } else {
                let source = CGDisplayMirrorsDisplay(displayID)
                if source != kCGNullDirectDisplay {
                    mirrorSources[displayID] = source
                    let unmirrored = CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay)
                    if unmirrored != .success {
                        Log.display.notice("Unmirroring display \(displayID) failed: \(unmirrored.rawValue)")
                    }
                }
            }
        }

        let result = configure(config, displayID, enabled)
        guard result == 0 else {
            Log.display.error("CGSConfigureDisplayEnabled(\(displayID), \(enabled), \(style.rawValue, privacy: .public)) failed: \(result)")
            CGCancelDisplayConfiguration(config)
            return false
        }

        var token: CGDisplayFadeReservationToken = 0
        var holdingFade = false
        if style == .holdFade {
            let reserved = CGAcquireDisplayFadeReservation(2, &token)
            holdingFade = reserved == .success
            if !holdingFade {
                Log.display.notice("CGAcquireDisplayFadeReservation failed: \(reserved.rawValue)")
            }
        }

        let start = Date()
        let completed = CGCompleteDisplayConfiguration(config, style.option)
        let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
        if holdingFade { CGReleaseDisplayFadeReservation(token) }

        if completed != .success {
            Log.display.error("CGCompleteDisplayConfiguration(\(style.rawValue, privacy: .public)) failed: \(completed.rawValue)")
            return false
        }
        Log.display.info("Display \(displayID) \(enabled ? "connected" : "disconnected", privacy: .public) (\(style.rawValue, privacy: .public), \(milliseconds) ms)")
        return true
    }
}
