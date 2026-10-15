import Foundation
import CoreGraphics

/// Switches a display off "in software": macOS stops using it as if the cable
/// had been pulled, so windows move to the remaining screens and the monitor
/// sees no signal (most then go to sleep on their own). The other screens
/// stay on: the default fade-to-black of display configurations is disabled.
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
    @discardableResult
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) -> Bool {
        guard let configure = configureEnabled else { return false }

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }

        // By default a display configuration fades *every* screen to black
        // and back. Turn that off, so the other screens stay on while this
        // one is disconnected or reconnected.
        CGConfigureDisplayFadeEffect(config, 0, 0, 0, 0, 0)

        let result = configure(config, displayID, enabled)
        guard result == 0 else {
            Log.display.error("CGSConfigureDisplayEnabled(\(displayID), \(enabled)) failed: \(result)")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        if completed != .success {
            Log.display.error("CGCompleteDisplayConfiguration failed: \(completed.rawValue)")
        }
        return completed == .success
    }
}
