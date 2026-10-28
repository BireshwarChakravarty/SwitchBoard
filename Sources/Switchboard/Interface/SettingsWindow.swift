import SwiftUI
import AppKit

/// The Settings window, opened from the menu's gear button or ⌘,. It manages
/// its own NSWindow: SwiftUI's Settings scene doesn't reliably come to the
/// front in a menu-bar app.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(controller: DisplayController) {
        let window = self.window ?? Self.make(controller: controller)
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private static func make(controller: DisplayController) -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView(controller: controller, remote: controller.remote)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Switchboard Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        return window
    }
}

/// Settings, as a grouped form like System Settings.
struct SettingsView: View {
    @ObservedObject var controller: DisplayController
    @ObservedObject var remote: RemoteControl

    var body: some View {
        Form {
            general
            RemoteSettings(remote: remote)
            reset
            about
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .alert("Reset Switchboard?", isPresented: Binding(
            get: { controller.confirmingReset },
            set: { if !$0 { controller.cancelReset() } }
        )) {
            Button("Cancel", role: .cancel) { controller.cancelReset() }
            Button("Reset", role: .destructive) { controller.resetToDefaults() }
        } message: {
            Text("Every screen is switched back on at normal brightness, and all settings, screen options and paired iPhones are cleared.")
        }
    }

    private var general: some View {
        Section("General") {
            if LoginItem.isAvailable {
                Toggle("Start at Login", isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                ))
            }
            Toggle(isOn: Binding(
                get: { controller.brightnessKeysEnabled },
                set: { controller.setBrightnessKeysEnabled($0) }
            )) {
                Text("Keyboard Keys")
                Text("Brightness keys adjust the screen under the pointer. Volume keys adjust monitor speakers.")
            }
            if controller.brightnessKeysNeedPermission {
                PermissionRow(name: "Device Control") { controller.openAccessibilitySettings() }
            }
            if controller.inputMonitoringNeeded {
                PermissionRow(name: "Input Monitoring") { controller.openInputMonitoringSettings() }
            }
            Toggle(isOn: Binding(
                get: { controller.brightnessFollowsAppearance },
                set: { controller.setBrightnessFollowsAppearance($0) }
            )) {
                Text("Match Light & Dark Mode")
                Text("Remembers one brightness for Light Mode and another for Dark Mode.")
            }
        }
    }

    private var reset: some View {
        Section {
            LabeledContent {
                Button("Reset…", role: .destructive) { controller.askToReset() }
            } label: {
                Text("Reset to Defaults")
                Text("Switches every screen back on and clears all settings.")
            }
        }
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: controller.versionNumber)
            LabeledContent("Source Code") {
                Link("GitHub", destination: URL(string: "https://github.com/BireshwarChakravarty/SwitchBoard")!)
            }
        }
    }
}

/// A missing macOS permission, with a button to its Privacy & Security page.
private struct PermissionRow: View {
    let name: String
    let openSettings: () -> Void

    var body: some View {
        LabeledContent {
            Button("Open Privacy Settings…", action: openSettings)
        } label: {
            Label {
                Text("Needs \(name) access")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// iPhone Remote: the switch, and when it's on, the address, pairing code,
/// shortcuts and paired devices.
private struct RemoteSettings: View {
    @ObservedObject var remote: RemoteControl

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { remote.isEnabled },
                set: { remote.setEnabled($0) }
            )) {
                Text("Allow iPhone Remote")
                Text("Control your screens from Safari or Siri on an iPhone on the same network.")
            }
            if remote.isEnabled {
                if let problem = remote.problem {
                    Label {
                        Text(problem)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } else {
                    details
                }
            }
        } header: {
            Text("iPhone Remote")
        } footer: {
            if remote.isEnabled && remote.problem == nil {
                Text("Open the address in Safari on your iPhone and enter the pairing code. Then tap Share → Add to Home Screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        AddressRow(title: "Address", address: remote.address)
        if let fallback = remote.fallbackAddress {
            AddressRow(title: "IP Address", address: fallback)
        }
        LabeledContent("Pairing Code") {
            HStack(spacing: 10) {
                Text(Self.grouped(remote.code))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
                Button("New Code") { remote.newCode() }
            }
        }
        LabeledContent {
            Button(remote.isMakingShortcuts ? "Making Shortcuts…" : "Add Shortcuts…") {
                remote.addShortcuts()
            }
            .disabled(remote.isMakingShortcuts || !remote.isListening)
        } label: {
            Text("Siri & Shortcuts")
            if let status = remote.shortcutsStatus {
                Text(status)
            } else {
                Text("Adds On, Off and Brightness shortcuts for each screen.")
            }
        }
        LabeledContent {
            Button("Forget All") { remote.forgetPairedDevices() }
                .disabled(remote.pairedCount == 0)
        } label: {
            Text("Paired Devices")
            Text(remote.pairedCount == 0 ? "None"
                 : remote.pairedCount == 1 ? "1 device" : "\(remote.pairedCount) devices")
        }
    }

    /// "123456" → "123 456", easier to read across a room.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// An address to open on the iPhone, with a copy button.
private struct AddressRow: View {
    let title: String
    let address: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(address)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(title)")
                .accessibilityLabel(Text("Copy \(title)"))
            }
        }
    }
}
