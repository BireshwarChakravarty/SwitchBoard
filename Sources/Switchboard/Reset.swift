import Foundation
import CoreGraphics

/// Undoes what this app, under any of its names, may have done to the
/// screens: reconnects screens it disconnected in software, removes software
/// dimming, and wakes monitors it put into DDC standby.
///
/// `make-app.sh` runs this (`Switchboard --reset`) before a clean install;
/// Reset to Defaults in the menu uses it too.
enum Reset {
    /// Settings domains of this app and its earlier names.
    static let domains = [
        "app.switchboard.Switchboard",
        "app.dimmer.Dimmer",
        "app.displaycontrol.DisplayControl",
        "app.displaytoggle.DisplayToggle"
    ]

    static func restoreScreens() {
        // 1. Reconnect every screen any version disconnected.
        var disconnected = Set<CGDirectDisplayID>()
        for domain in domains {
            let defaults = domain == Bundle.main.bundleIdentifier
                ? UserDefaults.standard
                : UserDefaults(suiteName: domain)
            let stored = defaults?.array(forKey: Preferences.disconnectedKey) as? [NSNumber] ?? []
            disconnected.formUnion(stored.map(\.uint32Value))
        }
        for id in disconnected {
            SoftwareDisconnect.setEnabled(true, displayID: id, scope: .session)
        }

        // 2. Remove software dimming.
        CGDisplayRestoreColorSyncSettings()

        // 3. Wake every external monitor that answers DDC/CI (harmless if
        //    it's already on).
        let ddc = DDC.makeController()
        for id in Displays.online() where CGDisplayIsBuiltin(id) == 0 {
            ddc.setPower(.on, for: DisplayIdentity(id: id, name: "display \(id)"))
        }
    }
}
