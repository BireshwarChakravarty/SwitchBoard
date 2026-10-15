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

    /// Enable (reconnect) or disable (disconnect) a display. Returns true on success.
    ///
    /// Tries first without the fade, so other screens stay on. If macOS
    /// rejects that, it retries with the default fade, which always worked.
    @discardableResult
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) -> Bool {
        if apply(enabled, displayID: displayID, fade: false) { return true }
        Log.display.notice("Display \(displayID): retrying with the default fade")
        return apply(enabled, displayID: displayID, fade: true)
    }

    private static func apply(_ enabled: Bool, displayID: CGDirectDisplayID, fade: Bool) -> Bool {
        guard let configure = configureEnabled else { return false }

        var config: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&config)
        guard begun == .success, let config else {
            Log.display.error("CGBeginDisplayConfiguration failed: \(begun.rawValue)")
            return false
        }

        if !fade {
            // By default a display configuration fades every screen to black
            // and back; turn that off.
            let faded = CGConfigureDisplayFadeEffect(config, 0, 0, 0, 0, 0)
            if faded != .success {
                Log.display.notice("CGConfigureDisplayFadeEffect failed: \(faded.rawValue)")
            }
        }

        let result = configure(config, displayID, enabled)
        guard result == 0 else {
            Log.display.error("CGSConfigureDisplayEnabled(\(displayID), \(enabled), fade: \(fade)) failed: \(result)")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        if completed != .success {
            Log.display.error("CGCompleteDisplayConfiguration(fade: \(fade)) failed: \(completed.rawValue)")
            return false
        }
        Log.display.info("Display \(displayID) \(enabled ? "connected" : "disconnected", privacy: .public) (fade: \(fade))")
        return true
    }
}
