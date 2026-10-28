import SwiftUI
import AppKit

/// Every screen. The selected one opens into a card with its controls; click
/// another screen to switch.
struct ScreenList: View {
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
                    let isSelected = display.id == controller.selectedDisplay?.id
                    VStack(alignment: .leading, spacing: 14) {
                        ScreenRow(display: display, controller: controller)
                        if isSelected {
                            ScreenControls(display: display, controller: controller)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .fill(isSelected ? Theme.card : Color.clear)
                    )
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: controller.selectedDisplay?.id)
    }
}

/// A screen's tile, name, status and power switch. Click to select;
/// right-click for its options.
struct ScreenRow: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        HStack(spacing: 12) {
            ScreenTile(
                symbol: display.isBuiltIn ? "laptopcomputer" : "display",
                isOn: display.isOn
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if display.isMain {
                        Tag(text: "MAIN", help: "Main display (has the menu bar)")
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
        .contentShape(Rectangle())
        .onTapGesture { controller.select(display.id) }
        .contextMenu { ScreenOptions(display: display, controller: controller) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// What a screen is doing, under its name: "2560 × 1440 · 160 Hz",
/// "Mirror of …", "Standby", or a problem in orange.
struct StatusLine: View {
    let display: ManagedDisplay

    var body: some View {
        if let problem = display.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11.5))
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var text: String {
        var parts: [String] = []
        if !display.isOn {
            parts.append(display.offMethod == .standby ? "Standby" : "Disconnected")
        } else if let mirror = display.mirrorNote, mirror.hasPrefix("Mirror of") {
            parts.append(mirror)
        } else {
            if display.isBuiltIn { parts.append("Built-in") }
            if let index = display.resolutionIndex, display.resolutions.indices.contains(index) {
                parts.append(display.resolutions[index].label)
            }
            if let rate = DisplayModes.refreshRate(of: display.id) { parts.append("\(rate) Hz") }
        }
        if display.isOn && display.isPowerOnly { parts.append("On and off only") }
        if display.autoOff { parts.append("Off while locked") }
        return parts.isEmpty ? "On" : parts.joined(separator: " · ")
    }
}

/// Per-screen options, from a right-click.
struct ScreenOptions: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        if display.canToggle {
            Picker("Switch Off By", selection: Binding(
                get: { display.offMethod },
                set: { controller.setOffMethod($0, for: display.id) }
            )) {
                Text("Standby").tag(OffMethod.standby)
                Text("Disconnect").tag(OffMethod.disconnect)
            }
            Toggle("Switch Off While Locked or Asleep", isOn: Binding(
                get: { display.autoOff },
                set: { controller.setAutoOff($0, for: display.id) }
            ))
            if display.offMethod != .standby {
                Toggle("Dim in Software", isOn: Binding(
                    get: { display.softwareDimming },
                    set: { controller.setSoftwareDimming($0, for: display.id) }
                ))
            }
            Button(display.showsSwitch ? "Hide Power Switch" : "Show Power Switch") {
                controller.setSwitchVisible(!display.showsSwitch, for: display.id)
            }
        }
    }
}
