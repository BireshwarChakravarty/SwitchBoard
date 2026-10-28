import SwiftUI
import AppKit

/// Every screen: badge, name, status and power switch. Click to select.
struct ScreensCard: View {
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

struct ScreenRow: View {
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
struct StatusLine: View {
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
struct ScreenOptions: View {
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
