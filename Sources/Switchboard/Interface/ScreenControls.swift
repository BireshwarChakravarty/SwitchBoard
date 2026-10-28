import SwiftUI
import AppKit

/// The selected screen's controls, inside its card: Brightness, Contrast,
/// Volume and Resolution, then how it switches off and its other options.
struct ScreenControls: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if display.isOn {
                levels
            } else {
                offState
            }
            if display.canToggle {
                Divider()
                ScreenOptionsPanel(display: display, controller: controller)
            }
        }
        .animation(.snappy(duration: 0.25), value: display.isOn)
    }

    @ViewBuilder
    private var levels: some View {
        let hasAny = display.combinedBrightness != nil || display.contrast != nil
            || display.volume != nil || display.resolutions.count > 1
        if !hasAny {
            Text(display.isBuiltIn
                 ? "Use the system's brightness controls for the built-in display."
                 : display.isPowerOnly
                 ? "Switchboard only switches this monitor on and off. Set its brightness with its own buttons."
                 : "Reading the monitor's settings…")
                .fixedSize(horizontal: false, vertical: true)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        if let level = display.combinedBrightness {
            ControlBlock(title: "Brightness", value: Self.percent(level)) {
                LevelSlider(value: level) { controller.setBrightness($0, for: display.id) }
            }
        }
        if let contrast = display.contrast {
            ControlBlock(title: "Contrast", value: Self.percent(contrast)) {
                LevelSlider(value: Self.fraction(contrast)) {
                    controller.setVCP(VCP.contrast, to: Self.raw($0, of: contrast), for: display.id)
                }
            }
        }
        if let volume = display.volume {
            ControlBlock(title: "Volume", value: Self.percent(volume)) {
                LevelSlider(value: Self.fraction(volume)) {
                    controller.setVCP(VCP.volume, to: Self.raw($0, of: volume), for: display.id)
                }
            }
        }
        if display.resolutions.count > 1, let index = display.resolutionIndex,
           display.resolutions.indices.contains(index) {
            ResolutionStepper(display: display, index: index, controller: controller)
        }
    }

    @ViewBuilder
    private var offState: some View {
        HStack {
            Text(display.offMethod == .standby ? "In standby." : "Switched off.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if display.canToggle && !display.showsSwitch {
                Button("Switch On") { controller.setPower(on: true, for: display.id) }
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
}

/// Resolution as − and + around the current size ("Looks like" in System
/// Settings): − makes everything larger, + gives more space.
struct ResolutionStepper: View {
    let display: ManagedDisplay
    let index: Int
    @ObservedObject var controller: DisplayController

    var body: some View {
        let resolution = display.resolutions[index]
        HStack {
            Text("Resolution")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            HStack(spacing: 0) {
                step("minus", help: "Larger Text", to: index - 1)
                Text(resolution.label + (resolution.isHiDPI ? "" : " · Low Res"))
                    .font(.system(size: 12).monospacedDigit())
                    .frame(minWidth: 92)
                    .contentTransition(.numericText())
                step("plus", help: "More Space", to: index + 1)
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Resolution \(resolution.label)"))
    }

    private func step(_ symbol: String, help: String, to target: Int) -> some View {
        Button {
            controller.previewResolution(target, for: display.id)
            controller.applyResolution(for: display.id)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!display.resolutions.indices.contains(target))
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// How the screen switches off, and its other options behind More Options.
struct ScreenOptionsPanel: View {
    let display: ManagedDisplay
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Switch off by")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Switch Off By", selection: Binding(
                    get: { display.offMethod },
                    set: { controller.setOffMethod($0, for: display.id) }
                )) {
                    Text("Standby").tag(OffMethod.standby)
                    Text("Disconnect").tag(OffMethod.disconnect)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            Button {
                controller.toggleScreenOptions()
            } label: {
                HStack(spacing: 4) {
                    Text("More Options")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(controller.screenOptionsExpanded ? 90 : 0))
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if controller.screenOptionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    SwitchRow(title: "Switch Off While Locked or Asleep", isOn: Binding(
                        get: { display.autoOff },
                        set: { controller.setAutoOff($0, for: display.id) }
                    ))
                    SwitchRow(title: "Hide Power Switch", isOn: Binding(
                        get: { controller.isSwitchHidden(display.id) },
                        set: { controller.setSwitchVisible(!$0, for: display.id) }
                    ))
                    if display.offMethod != .standby {
                        // No DDC/CI: offer software dimming, off by default.
                        SwitchRow(title: "Dim in Software", isOn: Binding(
                            get: { display.softwareDimming },
                            set: { controller.setSoftwareDimming($0, for: display.id) }
                        ))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: controller.screenOptionsExpanded)
    }
}
