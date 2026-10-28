import SwiftUI
import AppKit

/// The Settings window, opened from the menu or ⌘,. It manages its own
/// NSWindow: SwiftUI's Settings scene doesn't reliably come to the front in
/// a menu-bar app.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let navigation = SettingsNavigation()

    /// Show the window, optionally on a given pane.
    func show(controller: DisplayController, pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        let window = self.window ?? make(controller: controller)
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make(controller: DisplayController) -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(
            controller: controller, remote: controller.remote, navigation: navigation
        ))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Switchboard Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        return window
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, keyboard, remote, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .keyboard: "Keyboard"
        case .remote: "iPhone Remote"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .keyboard: "keyboard.fill"
        case .remote: "iphone"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .general: Color(white: 0.55)
        case .keyboard: Color(red: 0.36, green: 0.42, blue: 0.55)
        case .remote: Theme.signal
        case .about: Color(white: 0.55)
        }
    }
}

/// The selected pane. A class, because the app avoids @State (see
/// SwitchboardApp's design notes).
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
}

/// Settings: a sidebar of panes, like System Settings.
struct SettingsView: View {
    @ObservedObject var controller: DisplayController
    @ObservedObject var remote: RemoteControl
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding<SettingsPane?>(
                get: { navigation.pane },
                set: { if let pane = $0 { navigation.pane = pane } }
            )) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsIcon(symbol: pane.symbol, color: pane.color)
                    }
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            Group {
                switch navigation.pane {
                case .general: GeneralPane(controller: controller)
                case .keyboard: KeyboardPane(controller: controller)
                case .remote: RemotePane(remote: remote, controller: controller)
                case .about: AboutPane(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 500)
        .tint(Theme.signal)
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
}

/// A pane's symbol on a small coloured tile, as in System Settings.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.gradient))
    }
}

private struct GeneralPane: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        Form {
            Section {
                if LoginItem.isAvailable {
                    Toggle("Start at Login", isOn: Binding(
                        get: { controller.launchAtLogin },
                        set: { controller.setLaunchAtLogin($0) }
                    ))
                }
                Toggle(isOn: Binding(
                    get: { controller.brightnessFollowsAppearance },
                    set: { controller.setBrightnessFollowsAppearance($0) }
                )) {
                    Text("Match Light & Dark Mode")
                    Text("Remembers one brightness for Light Mode and another for Dark Mode.")
                }
            }
            Section {
                LabeledContent {
                    Button("Reset…", role: .destructive) { controller.askToReset() }
                } label: {
                    Text("Reset to Defaults")
                    Text("Switches every screen back on and clears all settings.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardPane: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { controller.brightnessKeysEnabled },
                    set: { controller.setBrightnessKeysEnabled($0) }
                )) {
                    Text("Keyboard Keys")
                    Text("Use the brightness and volume keys with external monitors.")
                }
                if controller.brightnessKeysNeedPermission {
                    PermissionRow(name: "Device Control") { controller.openAccessibilitySettings() }
                }
                if controller.inputMonitoringNeeded {
                    PermissionRow(name: "Input Monitoring") { controller.openInputMonitoringSettings() }
                }
            }
            Section {
                LabeledContent("Brightness", value: "Brightness keys (F1, F2)")
                LabeledContent("Finer steps", value: "⇧⌥ with a brightness key")
                LabeledContent("Volume and mute", value: "Monitor speakers, when sound plays through them")
            } header: {
                Text("Keys")
            } footer: {
                Text("Brightness keys adjust the screen under the pointer and any screen mirroring it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

private struct RemotePane: View {
    @ObservedObject var remote: RemoteControl
    @ObservedObject var controller: DisplayController

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { remote.isEnabled },
                    set: { remote.setEnabled($0) }
                )) {
                    Text("Allow iPhone Remote")
                    Text("Control your screens from Safari or Siri on an iPhone on the same network.")
                }
                if remote.isEnabled, let problem = remote.problem {
                    Label {
                        Text(problem)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            if remote.isEnabled && remote.problem == nil {
                Section {
                    address
                } footer: {
                    Text("Enter the pairing code on the iPhone, then tap Share → Add to Home Screen to use it like an app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Pairing Code") {
                        HStack(spacing: 10) {
                            Text(Self.grouped(remote.code))
                                .font(.title3.monospacedDigit().weight(.semibold))
                                .textSelection(.enabled)
                            Button("New Code") { remote.newCode() }
                        }
                    }
                    LabeledContent {
                        Menu(remote.isMakingShortcuts ? "Making Shortcut…" : "Add Shortcut") {
                            ForEach(shortcutScreens) { screen in
                                Button(screen.name) { remote.addShortcut(for: screen.id) }
                            }
                        }
                        .fixedSize()
                        .disabled(remote.isMakingShortcuts || !remote.isListening || shortcutScreens.isEmpty)
                    } label: {
                        Text("Siri Shortcut")
                        Text(remote.shortcutsStatus
                             ?? "“Toggle Monitor” switches the screen you choose on or off. Siri answers “Monitor On” or “Monitor Off”.")
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
            }
        }
        .formStyle(.grouped)
    }

    /// Screens with a power switch, other screens before the main display.
    private var shortcutScreens: [ManagedDisplay] {
        controller.displays
            .filter { $0.canToggle && !controller.isSwitchHidden($0.id) }
            .sorted { !$0.isMain && $1.isMain }
    }

    /// A QR code for the iPhone's camera, with the addresses beside it.
    private var address: some View {
        HStack(alignment: .center, spacing: 16) {
            if let code = QRCode.image(for: remote.address) {
                Image(nsImage: code)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 104, height: 104)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                    .accessibilityLabel(Text("QR code for \(remote.address)"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan with the iPhone's camera, or open in Safari:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                AddressLine(address: remote.address)
                if let fallback = remote.fallbackAddress {
                    AddressLine(address: fallback)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// "123456" → "123 456", easier to read across a room.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// An address to open on the iPhone, with a copy button.
private struct AddressLine: View {
    let address: String

    var body: some View {
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
            .help("Copy Address")
            .accessibilityLabel(Text("Copy \(address)"))
        }
    }
}

private struct AboutPane: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Switchboard")
                .font(.title.weight(.semibold))
            Text(controller.versionLabel)
                .foregroundStyle(.secondary)
            Text("Switch external screens on and off, and set their brightness, from the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
                .padding(.top, 4)
            Link("github.com/BireshwarChakravarty/SwitchBoard",
                 destination: URL(string: "https://github.com/BireshwarChakravarty/SwitchBoard")!)
                .padding(.top, 6)
            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
    }
}
