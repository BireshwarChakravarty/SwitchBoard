import SwiftUI
import AppKit

@main
struct SwitchboardApp: App {
    @StateObject private var controller = DisplayController()

    init() {
        // `Switchboard --reset`: put every screen back to normal and exit
        // (used by make-app.sh before a clean install).
        if CommandLine.arguments.contains("--reset") {
            Reset.restoreScreens()
            exit(0)
        }
        // Menu-bar-only app: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(nsImage: MenuBarIcon.make())
        }
        .menuBarExtraStyle(.window)
    }
}

// Design notes
//
// - "Signal": the menu is a list of screens; the selected one opens into a
//   card with its controls, and Settings and Quit sit below as menu items.
//   Settings is a separate window with a sidebar, like System Settings, so
//   the menu stays about screens.
// - The menu window's own material is the only glass; cards are a faint
//   fill. Hierarchy comes from grouping and type, not decoration.
// - Colour is reserved for state: Signal amber (Theme.signal) marks what's
//   on (switches, lit screen tiles, slider fills), orange marks a problem,
//   and everything else uses the system's label colours, so it reads
//   correctly in Light and Dark mode.
// - The app icon, the menu-bar icon and the iPhone remote share one motif:
//   a monitor whose screen is half lit.
// - No @State anywhere: on recent SDKs SwiftUI's @State is a macro whose
//   plugin ships only with full Xcode, so it fails to build with just the
//   Command Line Tools. All view state lives in DisplayController.
