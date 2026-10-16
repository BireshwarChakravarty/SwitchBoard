import Foundation
import CoreGraphics

/// Switches a display off "in software": macOS stops using it as if the cable
/// had been pulled, so windows move to the remaining screens and the monitor
/// sees no signal (most then go to sleep on their own).
///
/// This is how monitors without DDC/CI are switched off. It uses the private
/// `CGSConfigureDisplayEnabled`, looked up at runtime so the app still builds
/// and runs if a macOS release removes it.
///
/// The change is applied for this app only (`.forAppOnly`). Two reasons:
/// - Other screens stay on. Applying it for the session or permanently makes
///   macOS save and reload the whole display setup, which blanks every screen.
/// - It can't get stuck: macOS reconnects the screen itself when the app quits
///   or crashes.
enum SoftwareDisconnect {
    /// How long a change lasts.
    enum Scope {
        /// Until the app quits (the normal case).
        case app
        /// For the login session. Only for undoing a session-wide disconnect
        /// left by an older version of the app.
        case session

        var option: CGConfigureOption { self == .app ? .forAppOnly : .forSession }
    }

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
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID, scope: Scope = .app) -> Bool {
        guard let configure = configureEnabled else { return false }

        var config: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&config)
        guard begun == .success, let config else {
            Log.display.error("CGBeginDisplayConfiguration failed: \(begun.rawValue)")
            return false
        }

        let result = configure(config, displayID, enabled)
        guard result == 0 else {
            Log.display.error("CGSConfigureDisplayEnabled(\(displayID), \(enabled)) failed: \(result)")
            CGCancelDisplayConfiguration(config)
            return false
        }

        let completed = CGCompleteDisplayConfiguration(config, scope.option)
        guard completed == .success else {
            Log.display.error("CGCompleteDisplayConfiguration failed: \(completed.rawValue)")
            return false
        }
        Log.display.info("Display \(displayID) \(enabled ? "connected" : "disconnected", privacy: .public)")
        return true
    }
}
