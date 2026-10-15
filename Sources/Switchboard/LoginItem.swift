import Foundation
import ServiceManagement

/// Wraps "launch at login" via SMAppService.
///
/// This only works when the app runs as a proper, signed .app bundle (see
/// make-app.sh). When run via `swift run` there is no bundle to register, so
/// `isAvailable` is false and the toggle is hidden.
enum LoginItem {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Turns "Start at login" on the first time the installed app runs from
    /// /Applications. After that the menu checkbox is the user's choice.
    static func enableOnFirstInstalledLaunch() {
        let key = "didEnableLoginItemOnFirstLaunch"
        guard isAvailable,
              Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
