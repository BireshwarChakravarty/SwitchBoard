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
///
/// A screen that mirrors another is taken out of its mirror set in the same
/// configuration that disconnects it, and put back in the one that
/// reconnects it. Otherwise macOS rebuilds the mirror set around the other
/// screen, which briefly blanks it.
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

    /// The screen each disconnected screen mirrored, to mirror again when it's
    /// reconnected. Only touched from the main thread. Not persisted: an
    /// app-only disconnect, mirroring included, is undone by macOS when the
    /// app exits.
    nonisolated(unsafe) private static var mirrorSources: [CGDirectDisplayID: CGDirectDisplayID] = [:]

    /// Enable (reconnect) or disable (disconnect) a display. Returns true on success.
    @discardableResult
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID, scope: Scope = .app) -> Bool {
        guard let configure = configureEnabled else { return false }

        if !enabled {
            let source = CGDisplayMirrorsDisplay(displayID)
            if source != kCGNullDirectDisplay {
                // Leave the mirror set and switch off in one step.
                let done = apply(scope: scope, "unmirror and disconnect \(displayID)") { config in
                    CGConfigureDisplayMirrorOfDisplay(config, displayID, kCGNullDirectDisplay) == .success
                        && configure(config, displayID, false) == 0
                }
                if done {
                    mirrorSources[displayID] = source
                    return true
                }
                Log.display.notice("Display \(displayID): disconnecting without unmirroring first")
            }
            return apply(scope: scope, "disconnect \(displayID)") { configure($0, displayID, false) == 0 }
        }

        if let source = mirrorSources[displayID], CGDisplayIsOnline(source) != 0 {
            // Switch on and rejoin the mirror set in one step.
            let done = apply(scope: scope, "reconnect \(displayID) as a mirror of \(source)") { config in
                configure(config, displayID, true) == 0
                    && CGConfigureDisplayMirrorOfDisplay(config, displayID, source) == .success
            }
            if done {
                mirrorSources[displayID] = nil
                return true
            }
            Log.display.notice("Display \(displayID): reconnecting, then mirroring separately")
            guard apply(scope: scope, "reconnect \(displayID)", { configure($0, displayID, true) == 0 }) else {
                return false
            }
            mirrorSources[displayID] = nil
            apply(scope: scope, "mirror \(displayID) of \(source)") {
                CGConfigureDisplayMirrorOfDisplay($0, displayID, source) == .success
            }
            return true
        }
        mirrorSources[displayID] = nil
        return apply(scope: scope, "reconnect \(displayID)") { configure($0, displayID, true) == 0 }
    }

    /// Run `steps` in one display configuration and complete it. Returns
    /// false (and cancels) if a step or the configuration fails.
    @discardableResult
    private static func apply(scope: Scope, _ description: String,
                              _ steps: (CGDisplayConfigRef) -> Bool) -> Bool {
        var config: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&config)
        guard begun == .success, let config else {
            Log.display.error("CGBeginDisplayConfiguration failed: \(begun.rawValue)")
            return false
        }
        guard steps(config) else {
            Log.display.error("Couldn't \(description, privacy: .public): a step was rejected")
            CGCancelDisplayConfiguration(config)
            return false
        }
        let start = Date()
        let completed = CGCompleteDisplayConfiguration(config, scope.option)
        let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
        guard completed == .success else {
            Log.display.error("Couldn't \(description, privacy: .public): \(completed.rawValue)")
            return false
        }
        Log.display.info("Done: \(description, privacy: .public) (\(milliseconds) ms)")
        return true
    }
}
