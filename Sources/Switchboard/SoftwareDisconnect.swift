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

    /// How a display configuration fades the screens while it's applied.
    private enum Fade: CustomStringConvertible {
        /// A fade too short to see (10 ms), so other screens appear to stay on.
        case minimal
        /// macOS's default: every screen fades to black and back (~0.8 s).
        case standard

        var description: String { self == .minimal ? "minimal" : "standard" }
    }

    /// Enable (reconnect) or disable (disconnect) a display. Returns true on success.
    ///
    /// Tries a minimal fade first, so other screens don't visibly go black. If
    /// macOS rejects that, it retries with the default fade, which always works.
    /// (Turning the fade off entirely fails with kCGErrorNotImplemented on
    /// recent macOS.)
    @discardableResult
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) -> Bool {
        if apply(enabled, displayID: displayID, fade: .minimal) { return true }
        Log.display.notice("Display \(displayID): retrying with the standard fade")
        return apply(enabled, displayID: displayID, fade: .standard)
    }

    private static func apply(_ enabled: Bool, displayID: CGDirectDisplayID, fade: Fade) -> Bool {
        guard let configure = configureEnabled else { return false }

        var config: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&config)
        guard begun == .success, let config else {
            Log.display.error("CGBeginDisplayConfiguration failed: \(begun.rawValue)")
            return false
        }

        if fade == .minimal {
            let faded = CGConfigureDisplayFadeEffect(config, 0.01, 0.01, 0, 0, 0)
            if faded != .success {
                Log.display.notice("CGConfigureDisplayFadeEffect failed: \(faded.rawValue)")
            }
        }

        let result = configure(config, displayID, enabled)
        guard result == 0 else {
            Log.display.error("CGSConfigureDisplayEnabled(\(displayID), \(enabled), fade: \(fade.description, privacy: .public)) failed: \(result)")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        if completed != .success {
            Log.display.error("CGCompleteDisplayConfiguration(fade: \(fade.description, privacy: .public)) failed: \(completed.rawValue)")
            return false
        }
        Log.display.info("Display \(displayID) \(enabled ? "connected" : "disconnected", privacy: .public) (fade: \(fade.description, privacy: .public))")
        return true
    }
}
