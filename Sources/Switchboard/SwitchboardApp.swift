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

// No @State anywhere in the UI: on recent SDKs SwiftUI's @State is a macro
// whose plugin ships only with full Xcode, so it fails to build with just the
// Command Line Tools. All view state lives in DisplayController.

/// The menu: a glass card of screens, a card of options, and a footer.
struct MenuContent: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    screensCard
                    if let level = controller.allScreensBrightness {
                        allScreensCard(level)
                    }
                    optionsCard
                }
            }
            footer
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { controller.refresh() }
    }

    // MARK: Screens

    private var screensCard: some View {
        VStack(spacing: 0) {
            if controller.displays.isEmpty {
                ContentUnavailableView(
                    "No Screens",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("Connect a monitor to control it here.")
                )
                .padding(.vertical, 8)
            } else {
                ForEach(controller.displays) { display in
                    DisplayRow(display: display, controller: controller)
                    if display.id != controller.displays.last?.id {
                        Divider().padding(.leading, 58).padding(.trailing, 14)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: All screens

    private func allScreensCard(_ level: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Brightness")
                    .font(.callout.weight(.semibold))
                Text("All Screens")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            SliderRow(icon: "sun.max.fill", label: "Brightness, all screens",
                      value: "\(Int((level * 100).rounded()))%") {
                Slider(value: Binding(
                    get: { level },
                    set: { controller.setAllScreensBrightness($0) }
                ), in: 0...1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: Options

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            OptionRow(
                icon: "keyboard",
                title: "Keyboard Keys",
                detail: "Brightness and monitor volume · ⇧⌥ for fine steps",
                isOn: Binding(
                    get: { controller.brightnessKeysEnabled },
                    set: { controller.setBrightnessKeysEnabled($0) }
                )
            )
            if controller.brightnessKeysNeedPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Needs Accessibility access")
                        .font(.callout)
                    Spacer()
                    Button("Open Settings") { controller.openAccessibilitySettings() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            if LoginItem.isAvailable {
                Divider().padding(.leading, 58).padding(.trailing, 14)
                OptionRow(
                    icon: "power.circle",
                    title: "Start at Login",
                    detail: nil,
                    isOn: Binding(
                        get: { controller.launchAtLogin },
                        set: { controller.setLaunchAtLogin($0) }
                    )
                )
            }
        }
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if controller.confirmingReset {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reset to Defaults?")
                        .font(.callout.weight(.semibold))
                    Text("Reconnects and restores every screen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { controller.cancelReset() }
                    .buttonStyle(.glass)
                Button("Reset") { controller.resetToDefaults() }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Switchboard")
                        .font(.callout.weight(.semibold))
                    Text("Right-click a screen for options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CircleButton(icon: "arrow.counterclockwise", help: "Reset to Defaults…") {
                    controller.askToReset()
                }
                CircleButton(icon: "arrow.clockwise", help: "Refresh") {
                    controller.refresh()
                }
                CircleButton(icon: "power", help: "Quit Switchboard") {
                    // Never leave a screen disconnected or dimmed behind us.
                    controller.prepareToQuit()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 4)
        .animation(.snappy(duration: 0.2), value: controller.confirmingReset)
    }
}

/// A round glass icon button.
struct CircleButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// An options row: icon badge, title and detail, and a switch.
struct OptionRow: View {
    let icon: String
    let title: String
    let detail: String?
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, isActive: isOn.wrappedValue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A round symbol badge, filled with the accent colour when active.
struct IconBadge: View {
    let symbol: String
    let isActive: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle().fill(isActive ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary))
            )
            .animation(.snappy(duration: 0.2), value: isActive)
    }
}

/// One screen: badge, name, status, "Main" tag and switch, then its sliders.
/// Right-click for per-screen options.
struct DisplayRow: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if display.isOn && hasSliders {
                VStack(spacing: 6) { sliders }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle()) // right-click works anywhere on the row
        .contextMenu { options }
        .animation(.snappy(duration: 0.25), value: display.isOn)
    }

    private var header: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: display.isBuiltIn ? "laptopcomputer" : "display", isActive: display.isOn)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if display.isMain {
                        Text("Main")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                            .help("Main display (has the menu bar)")
                    }
                }
                if let problem = display.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                } else if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if display.canToggle && display.showsSwitch {
                Toggle(display.name, isOn: Binding(
                    get: { display.isOn },
                    set: { controller.setPower(on: $0, for: display.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private var hasSliders: Bool {
        display.combinedBrightness != nil || display.contrast != nil
            || display.volume != nil || display.resolutions.count > 1
    }

    @ViewBuilder
    private var sliders: some View {
        if let level = display.combinedBrightness {
            SliderRow(icon: "sun.max.fill", label: "Brightness",
                      value: "\(Int((level * 100).rounded()))%") {
                Slider(value: Binding(
                    get: { level },
                    set: { controller.setBrightness($0, for: display.id) }
                ), in: 0...1)
            }
        }
        if let contrast = display.contrast {
            vcpSlider(VCP.contrast, contrast, icon: "circle.lefthalf.filled", label: "Contrast")
        }
        if let volume = display.volume {
            vcpSlider(VCP.volume, volume, icon: "speaker.wave.2.fill", label: "Volume")
        }
        if display.resolutions.count > 1, let index = display.resolutionIndex,
           display.resolutions.indices.contains(index) {
            let resolution = display.resolutions[index]
            SliderRow(icon: "arrow.up.left.and.arrow.down.right", label: "Resolution",
                      value: resolution.label, valueWidth: 86) {
                Slider(
                    value: Binding(
                        get: { Double(index) },
                        set: { controller.previewResolution(Int($0.rounded()), for: display.id) }
                    ),
                    in: 0...Double(display.resolutions.count - 1),
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { controller.applyResolution(for: display.id) }
                    }
                )
            }
        }
    }

    private func vcpSlider(_ vcp: UInt8, _ value: VCPValue, icon: String, label: String) -> some View {
        let percent = Int((Double(value.current) / Double(value.max) * 100).rounded())
        return SliderRow(icon: icon, label: label, value: "\(percent)%") {
            Slider(value: Binding(
                get: { Double(value.current) },
                set: { controller.setVCP(vcp, to: UInt16($0.rounded()), for: display.id) }
            ), in: 0...Double(value.max))
        }
    }

    @ViewBuilder
    private var options: some View {
        if display.canToggle {
            Button(display.showsSwitch ? "Hide Switch" : "Show Switch") {
                controller.setSwitchVisible(!display.showsSwitch, for: display.id)
            }
            Picker("Switch Off By", selection: Binding(
                get: { display.offMethod },
                set: { controller.setOffMethod($0, for: display.id) }
            )) {
                Text("DDC/CI Standby").tag(OffMethod.standby)
                Text("Disconnecting").tag(OffMethod.disconnect)
            }
            Toggle("Switch Off While Locked or Asleep", isOn: Binding(
                get: { display.autoOff },
                set: { controller.setAutoOff($0, for: display.id) }
            ))
            if display.brightness != nil || display.contrast != nil {
                Divider()
                Button("Restore Factory Brightness & Contrast") {
                    controller.restoreFactoryPicture(for: display.id)
                }
            }
        }
    }

    /// e.g. "Mirrored to <screen> · Off when locked", "Standby", "Disconnected".
    private var subtitle: String? {
        var parts: [String] = []
        if !display.isOn {
            parts.append(display.offMethod == .disconnect ? "Disconnected" : "Standby")
        } else if let mirrorNote = display.mirrorNote {
            parts.append(mirrorNote)
        }
        if display.isBuiltIn { parts.append("Built-in") }
        if display.autoOff { parts.append("Off when locked") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A slider with its symbol and a value readout ("72%", "2560 × 1440").
struct SliderRow<S: View>: View {
    let icon: String
    let label: String
    let value: String
    var valueWidth: CGFloat = 36
    @ViewBuilder let slider: () -> S

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32)
            slider()
                .controlSize(.small)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .help(label)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
    }
}
