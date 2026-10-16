import Foundation
import CoreGraphics

/// How a monitor is switched off.
enum OffMethod: String, Hashable {
    /// DDC/CI power standby: the monitor itself sleeps (power LED amber).
    case standby
    /// Software disconnect: macOS stops using the monitor (see SoftwareDisconnect).
    case disconnect
    /// Black out: the screen's picture is turned black through its gamma
    /// table. Instant, and macOS doesn't reconfigure displays, so a mirrored
    /// screen's source doesn't blank. The backlight stays on.
    case blackout
}

/// Per-monitor and app settings, remembered across launches. Monitors are
/// keyed by vendor/model/serial (`DisplayIdentity.key`), which stays the same
/// across reconnects and reboots, unlike CGDirectDisplayID.
enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let offMethodKey = "offMethod"
    private static let offMethodAutomaticKey = "offMethodAutomatic"
    private static let switchVisibleKey = "switchVisible"
    private static let autoOffKey = "autoOffWhenLockedOrAsleep"
    static let disconnectedKey = "disconnectedDisplayIDs"
    private static let brightnessKeysKey = "brightnessKeysEnabled"
    private static let disconnectStyleKey = "disconnectStyle"
    private static let followAppearanceKey = "brightnessFollowsAppearance"
    private static let appearanceBrightnessKey = "appearanceBrightness"

    static func offMethod(for monitor: String) -> OffMethod {
        let stored = defaults.dictionary(forKey: offMethodKey)?[monitor] as? String
        return stored.flatMap(OffMethod.init(rawValue:)) ?? .standby
    }

    /// `automatic`: Switchboard picked the method (and may pick a better one
    /// later) rather than the user.
    static func setOffMethod(_ method: OffMethod, for monitor: String, automatic: Bool = false) {
        set(method.rawValue, for: monitor, in: offMethodKey)
        set(automatic, for: monitor, in: offMethodAutomaticKey)
    }

    static func offMethodIsAutomatic(for monitor: String) -> Bool {
        defaults.dictionary(forKey: offMethodAutomaticKey)?[monitor] as? Bool ?? true
    }

    /// Nil when the user hasn't chosen; the caller picks the default.
    static func switchVisible(for monitor: String) -> Bool? {
        defaults.dictionary(forKey: switchVisibleKey)?[monitor] as? Bool
    }

    static func setSwitchVisible(_ visible: Bool, for monitor: String) {
        set(visible, for: monitor, in: switchVisibleKey)
    }

    /// Switch this monitor off when the screen locks or the Mac sleeps, and
    /// back on at unlock/wake.
    static func autoOff(for monitor: String) -> Bool {
        defaults.dictionary(forKey: autoOffKey)?[monitor] as? Bool ?? false
    }

    static func setAutoOff(_ enabled: Bool, for monitor: String) {
        set(enabled, for: monitor, in: autoOffKey)
    }

    /// How screens are disconnected (see SoftwareDisconnect.Style).
    static var disconnectStyle: SoftwareDisconnect.Style {
        get { defaults.string(forKey: disconnectStyleKey).flatMap(SoftwareDisconnect.Style.init(rawValue:)) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: disconnectStyleKey) }
    }

    static var brightnessKeysEnabled: Bool {
        // On unless turned off: on a Mac mini the keys do nothing otherwise.
        get { defaults.object(forKey: brightnessKeysKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: brightnessKeysKey) }
    }

    /// Each screen remembers one brightness for Light mode and one for Dark
    /// mode, and switches between them with the system appearance.
    static var brightnessFollowsAppearance: Bool {
        get { defaults.object(forKey: followAppearanceKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: followAppearanceKey) }
    }

    /// The combined brightness last used on this monitor in Light or Dark mode.
    static func brightness(for monitor: String, dark: Bool) -> Double? {
        let entry = defaults.dictionary(forKey: appearanceBrightnessKey)?[monitor] as? [String: Double]
        return entry?[dark ? "dark" : "light"]
    }

    static func setBrightness(_ level: Double, for monitor: String, dark: Bool) {
        var all = defaults.dictionary(forKey: appearanceBrightnessKey) ?? [:]
        var entry = all[monitor] as? [String: Double] ?? [:]
        entry[dark ? "dark" : "light"] = level
        all[monitor] = entry
        defaults.set(all, forKey: appearanceBrightnessKey)
    }

    /// Displays this app has disconnected in software, so they can be
    /// reconnected even if the app quit or crashed in the meantime.
    static var disconnectedDisplays: Set<CGDirectDisplayID> {
        get {
            let stored = defaults.array(forKey: disconnectedKey) as? [NSNumber] ?? []
            return Set(stored.map(\.uint32Value))
        }
        set {
            defaults.set(newValue.map { NSNumber(value: $0) }, forKey: disconnectedKey)
        }
    }

    private static func set(_ value: Any, for monitor: String, in key: String) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[monitor] = value
        defaults.set(all, forKey: key)
    }

    /// Forget every setting (Reset to Defaults).
    static func resetAll() {
        for key in [offMethodKey, offMethodAutomaticKey, switchVisibleKey, autoOffKey, disconnectedKey, brightnessKeysKey,
                    followAppearanceKey, appearanceBrightnessKey, disconnectStyleKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
