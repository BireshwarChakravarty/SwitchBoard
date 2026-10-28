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
// - Layout follows Control Center and BetterDisplay: a list of screens, then
//   the selected screen's controls as large titled sliders, then a footer
//   with Settings and Quit. Settings is a separate window, a grouped form like
//   System Settings, so the menu stays about screens.
// - Liquid Glass is used for the control layer only: each group is one glass
//   card. Hierarchy comes from grouping and type, not decoration.
// - Spacing is on a 4-point grid; corner radii are concentric (card 20,
//   content inset 6, inner highlight 14).
// - Colour is reserved for state: the accent fills an active badge, orange
//   marks a problem, everything else is the system's label colours, so it
//   reads correctly in Light and Dark mode.
// - No @State anywhere: on recent SDKs SwiftUI's @State is a macro whose
//   plugin ships only with full Xcode, so it fails to build with just the
//   Command Line Tools. All view state lives in DisplayController.
