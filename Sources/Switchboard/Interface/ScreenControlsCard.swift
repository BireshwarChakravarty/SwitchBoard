import SwiftUI
import AppKit

/// The selected screen's controls: Brightness, Contrast, Volume, Resolution.
struct ScreenControlsCard: View {
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
            if controller.screenOptionsExpanded && display.canToggle {
                ScreenOptionsPanel(display: display, controller: controller)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        .animation(.snappy(duration: 0.25), value: display.isOn)
        .animation(.snappy(duration: 0.25), value: controller.screenOptionsExpanded)
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
                // Options open inline rather than in a pop-up menu: menus
                // shown from a menu-bar window don't reliably run their actions.
                CircleButton(
                    icon: controller.screenOptionsExpanded ? "xmark" : "ellipsis",
                    help: controller.screenOptionsExpanded ? "Hide Options" : "Options for \(display.name)"
                ) {
                    controller.toggleScreenOptions()
                }
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
                 : display.isPowerOnly
                 ? "This monitor can only be switched on and off from the Mac. Set its brightness with its own buttons."
                 : "Reading the monitor's settings…")
                .fixedSize(horizontal: false, vertical: true)
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
struct AllScreensCard: View {
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

/// A screen's options, shown inline in its card (⋯).
struct ScreenOptionsPanel: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Switch Off By")
                    .font(.subheadline.weight(.medium))
                Picker("Switch Off By", selection: Binding(
                    get: { display.offMethod },
                    set: { controller.setOffMethod($0, for: display.id) }
                )) {
                    Text("Standby").tag(OffMethod.standby)
                    Text("Disconnect").tag(OffMethod.disconnect)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SwitchRow(title: "Switch off while locked or asleep", isOn: Binding(
                get: { display.autoOff },
                set: { controller.setAutoOff($0, for: display.id) }
            ))
            SwitchRow(title: "Hide power switch", isOn: Binding(
                get: { controller.isSwitchHidden(display.id) },
                set: { controller.setSwitchVisible(!$0, for: display.id) }
            ))
            if display.offMethod != .standby {
                // No DDC/CI: offer software dimming, off by default.
                SwitchRow(title: "Dim in software", isOn: Binding(
                    get: { display.softwareDimming },
                    set: { controller.setSoftwareDimming($0, for: display.id) }
                ))
            }
        }
    }
}
