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
//   the selected screen's controls as large titled sliders, then a collapsible
//   Settings section, then a footer.
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

private enum Metrics {
    static let width: CGFloat = 340
    static let cardRadius: CGFloat = 20
    static let cardInset: CGFloat = 6
    static let rowRadius: CGFloat = 14 // cardRadius - cardInset: concentric
    static let badge: CGFloat = 32
}

/// The menu.
struct MenuContent: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    ScreensCard(controller: controller)
                    if let display = controller.selectedDisplay {
                        ScreenControlsCard(display: display, controller: controller)
                    }
                    if let level = controller.allScreensBrightness {
                        AllScreensCard(level: level, controller: controller)
                    }
                    SettingsCard(controller: controller)
                }
            }
            Footer(controller: controller)
        }
        .padding(12)
        .frame(width: Metrics.width)
        .onAppear { controller.refresh() }
    }
}

// MARK: - Screens

/// Every screen: badge, name, status and power switch. Click to select.
private struct ScreensCard: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(spacing: 2) {
            if controller.displays.isEmpty {
                ContentUnavailableView(
                    "No Screens",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("Connect a monitor to control it here.")
                )
                .padding(.vertical, 8)
            } else {
                ForEach(controller.displays) { display in
                    ScreenRow(
                        display: display,
                        isSelected: display.id == controller.selectedDisplay?.id,
                        controller: controller
                    )
                }
            }
        }
        .padding(Metrics.cardInset)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
    }
}

private struct ScreenRow: View {
    let display: ManagedDisplay
    let isSelected: Bool
    @ObservedObject var controller: DisplayController

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(
                symbol: display.isBuiltIn ? "laptopcomputer" : "display",
                isActive: display.isOn
            )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if display.isMain {
                        Tag(text: "Main", help: "Main display (has the menu bar)")
                    }
                }
                StatusLine(display: display)
            }
            Spacer(minLength: 8)
            if display.canToggle && display.showsSwitch {
                Toggle(display.name, isOn: Binding(
                    get: { display.isOn },
                    set: { controller.setPower(on: $0, for: display.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .onTapGesture { controller.select(display.id) }
        .contextMenu { ScreenOptions(display: display, controller: controller) }
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// "Mirrored to …", "Standby", or a problem in orange.
private struct StatusLine: View {
    let display: ManagedDisplay

    var body: some View {
        if let problem = display.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let text {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var text: String? {
        var parts: [String] = []
        if !display.isOn {
            switch display.offMethod {
            case .standby: parts.append("Standby")
            case .disconnect: parts.append("Disconnected")
            case .blackout: parts.append("Blacked out")
            }
        } else if let mirrorNote = display.mirrorNote {
            parts.append(mirrorNote)
        }
        if display.isBuiltIn { parts.append("Built-in") }
        if display.autoOff { parts.append("Off when locked") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Per-screen options, from the ⋯ button or a right-click.
private struct ScreenOptions: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        if display.canToggle {
            Picker("Switch Off By", selection: Binding(
                get: { display.offMethod },
                set: { controller.setOffMethod($0, for: display.id) }
            )) {
                Text("DDC/CI Standby").tag(OffMethod.standby)
                Text("Disconnecting").tag(OffMethod.disconnect)
                Text("Blacking Out").tag(OffMethod.blackout)
            }
            Toggle("Switch Off While Locked or Asleep", isOn: Binding(
                get: { display.autoOff },
                set: { controller.setAutoOff($0, for: display.id) }
            ))
            Button(display.showsSwitch ? "Hide Power Switch" : "Show Power Switch") {
                controller.setSwitchVisible(!display.showsSwitch, for: display.id)
            }
            if display.brightness != nil || display.contrast != nil {
                Divider()
                Button("Restore Factory Brightness & Contrast") {
                    controller.restoreFactoryPicture(for: display.id)
                }
                Button("Restore All Factory Settings") {
                    controller.restoreFactoryPicture(for: display.id, everything: true)
                }
            }
        }
    }
}

// MARK: - Selected screen

/// The selected screen's controls: Brightness, Contrast, Volume, Resolution.
private struct ScreenControlsCard: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if display.isOn {
                controls
            } else {
                offState
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        .animation(.snappy(duration: 0.25), value: display.isOn)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .font(.headline)
                    .lineLimit(1)
                StatusLine(display: display)
            }
            Spacer()
            if display.canToggle {
                Menu {
                    ScreenOptions(display: display, controller: controller)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .fixedSize()
                .help("Options for \(display.name)")
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        let hasAny = display.combinedBrightness != nil || display.contrast != nil
            || display.volume != nil || display.resolutions.count > 1
        if !hasAny {
            Text(display.isBuiltIn
                 ? "Use the system's brightness controls for the built-in display."
                 : "Reading the monitor's settings…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let level = display.combinedBrightness {
            ControlBlock(title: display.brightness == nil ? "Brightness (Software)" : "Brightness (Combined)",
                         value: Self.percent(level)) {
                PillSlider(value: level, symbol: "sun.max.fill") {
                    controller.setBrightness($0, for: display.id)
                }
            }
        }
        if let contrast = display.contrast {
            ControlBlock(title: "Contrast", value: Self.percent(contrast)) {
                PillSlider(value: Self.fraction(contrast), symbol: "circle.lefthalf.filled") {
                    controller.setVCP(VCP.contrast, to: Self.raw($0, of: contrast), for: display.id)
                }
            }
        }
        if let volume = display.volume {
            ControlBlock(title: "Volume", value: Self.percent(volume)) {
                PillSlider(value: Self.fraction(volume), symbol: Self.volumeSymbol(volume)) {
                    controller.setVCP(VCP.volume, to: Self.raw($0, of: volume), for: display.id)
                }
            }
        }
        if display.resolutions.count > 1, let index = display.resolutionIndex,
           display.resolutions.indices.contains(index) {
            let count = display.resolutions.count
            let resolution = display.resolutions[index]
            ControlBlock(title: "Resolution",
                         value: resolution.label + (resolution.isHiDPI ? "" : " · Low Res")) {
                PillSlider(
                    value: Double(index) / Double(count - 1),
                    symbol: "arrow.up.left.and.arrow.down.right",
                    steps: count,
                    onChange: { fraction in
                        controller.previewResolution(Int((fraction * Double(count - 1)).rounded()), for: display.id)
                    },
                    onCommit: { controller.applyResolution(for: display.id) }
                )
            }
        }
    }

    private var offState: some View {
        HStack {
            Text(display.offMethod == .standby ? "In standby." : "Switched off.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            if display.canToggle {
                Button("Switch On") { controller.setPower(on: true, for: display.id) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
        }
    }

    private static func fraction(_ value: VCPValue) -> Double {
        Double(value.current) / Double(value.max)
    }

    private static func raw(_ fraction: Double, of value: VCPValue) -> UInt16 {
        UInt16((fraction * Double(value.max)).rounded())
    }

    private static func percent(_ level: Double) -> String {
        "\(Int((level * 100).rounded()))%"
    }

    private static func percent(_ value: VCPValue) -> String {
        percent(fraction(value))
    }

    private static func volumeSymbol(_ value: VCPValue) -> String {
        let level = fraction(value)
        return level < 0.01 ? "speaker.slash.fill"
            : level < 0.34 ? "speaker.wave.1.fill"
            : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// One brightness slider for every adjustable screen.
private struct AllScreensCard: View {
    let level: Double
    @ObservedObject var controller: DisplayController

    var body: some View {
        ControlBlock(title: "Brightness · All Screens", value: "\(Int((level * 100).rounded()))%") {
            PillSlider(value: level, symbol: "sun.max.fill") {
                controller.setAllScreensBrightness($0)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
    }
}

/// A titled control: "Brightness (Combined)   65%" above its slider.
private struct ControlBlock<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// A Control Center–style slider: a thick capsule that fills from the left,
/// with its symbol inside. Drag or click anywhere on it; VoiceOver can adjust
/// it with increment/decrement.
private struct PillSlider: View {
    let value: Double
    let symbol: String
    var steps: Int?
    let onChange: (Double) -> Void
    var onCommit: () -> Void = {}

    private static let height: CGFloat = 26

    init(value: Double, symbol: String, steps: Int? = nil,
         onChange: @escaping (Double) -> Void, onCommit: @escaping () -> Void = {}) {
        self.value = value
        self.symbol = symbol
        self.steps = steps
        self.onChange = onChange
        self.onCommit = onCommit
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fill = Self.height + (width - Self.height) * min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.white)
                    .frame(width: fill)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: Self.height, height: Self.height)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = (drag.location.x - Self.height / 2) / max(width - Self.height, 1)
                        onChange(snap(position))
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: Self.height)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: value)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((value * 100).rounded())) percent"))
        .accessibilityAdjustableAction { direction in
            let step = 1 / Double(max((steps ?? 17) - 1, 1))
            switch direction {
            case .increment: onChange(snap(value + step))
            case .decrement: onChange(snap(value - step))
            @unknown default: return
            }
            onCommit()
        }
    }

    private func snap(_ position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        guard let steps, steps > 1 else { return clamped }
        let last = Double(steps - 1)
        return (clamped * last).rounded() / last
    }
}

// MARK: - Settings

private struct SettingsCard: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(spacing: 0) {
            Button {
                controller.toggleSettings()
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "gearshape.fill", isActive: false)
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(controller.settingsExpanded ? 90 : 0))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if controller.settingsExpanded {
                VStack(spacing: 2) {
                    OptionRow(
                        icon: "keyboard",
                        title: "Keyboard Keys",
                        detail: "Brightness, and volume for monitor speakers",
                        isOn: Binding(
                            get: { controller.brightnessKeysEnabled },
                            set: { controller.setBrightnessKeysEnabled($0) }
                        )
                    )
                    if controller.brightnessKeysNeedPermission {
                        PermissionNotice(text: "Needs Device Control access") {
                            controller.openAccessibilitySettings()
                        }
                    }
                    if controller.inputMonitoringNeeded {
                        PermissionNotice(text: "Needs Input Monitoring access") {
                            controller.openInputMonitoringSettings()
                        }
                    }
                    if !controller.brightnessKeysNeedPermission && !controller.inputMonitoringNeeded,
                       let status = controller.keysStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 8 + Metrics.badge + 12)
                            .padding(.trailing, 8)
                            .padding(.bottom, 4)
                    }
                    OptionRow(
                        icon: "circle.lefthalf.filled",
                        title: "Match Light & Dark Mode",
                        detail: "A brightness for each appearance",
                        isOn: Binding(
                            get: { controller.brightnessFollowsAppearance },
                            set: { controller.setBrightnessFollowsAppearance($0) }
                        )
                    )
                    if LoginItem.isAvailable {
                        OptionRow(
                            icon: "power",
                            title: "Start at Login",
                            detail: nil,
                            isOn: Binding(
                                get: { controller.launchAtLogin },
                                set: { controller.setLaunchAtLogin($0) }
                            )
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Metrics.cardInset)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        .animation(.snappy(duration: 0.25), value: controller.settingsExpanded)
    }
}

/// "Needs … access" with a button to the right Privacy & Security page.
private struct PermissionNotice: View {
    let text: String
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
            Spacer()
            Button("Open Settings", action: openSettings)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.leading, 8 + Metrics.badge + 12)
        .padding(.trailing, 8)
        .padding(.bottom, 6)
    }
}

/// An option: badge, title and detail, and a switch.
private struct OptionRow: View {
    let icon: String
    let title: String
    let detail: String?
    let isOn: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, isActive: isOn.wrappedValue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

// MARK: - Footer

private struct Footer: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        HStack(spacing: 8) {
            if controller.confirmingReset {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reset to Defaults?")
                        .font(.subheadline.weight(.semibold))
                    Text("Restores every screen and forgets all settings")
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
                        .font(.subheadline.weight(.semibold))
                    Text(controller.versionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CircleButton(icon: "arrow.counterclockwise", help: "Reset to Defaults…") {
                    controller.askToReset()
                }
                CircleButton(icon: "arrow.clockwise", help: "Refresh Screens") {
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
        .padding(.horizontal, 6)
        .animation(.snappy(duration: 0.2), value: controller.confirmingReset)
    }
}

// MARK: - Shared pieces

/// A round glass icon button.
private struct CircleButton: View {
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

/// A round symbol badge, filled with the accent colour when active.
private struct IconBadge: View {
    let symbol: String
    let isActive: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .symbolEffect(.bounce, value: isActive)
            .frame(width: Metrics.badge, height: Metrics.badge)
            .background(
                Circle().fill(isActive ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary))
            )
            .animation(.snappy(duration: 0.2), value: isActive)
    }
}

/// A small capsule label, e.g. "Main".
private struct Tag: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .help(help)
    }
}
