import SwiftUI
import AppKit

struct SettingsCard: View {
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
                    RemoteSection(remote: controller.remote)
                    ResetRow(controller: controller)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Metrics.cardInset)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        .animation(.snappy(duration: 0.25), value: controller.settingsExpanded)
    }
}

/// iPhone Remote: the switch, and when it's on, where to point the phone
/// and the pairing code.
struct RemoteSection: View {
    @ObservedObject var remote: RemoteControl

    var body: some View {
        OptionRow(
            icon: "iphone",
            title: "iPhone Remote",
            detail: "Control screens from your iPhone and Shortcuts",
            isOn: Binding(
                get: { remote.isEnabled },
                set: { remote.setEnabled($0) }
            )
        )
        if remote.isEnabled {
            if let problem = remote.problem {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(problem)
                        .font(.caption)
                    Spacer()
                }
                .padding(.leading, 8 + Metrics.badge + 12)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("In Safari on your iPhone, open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Text(remote.address)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(remote.address, forType: .string)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                        }
                        if let fallback = remote.fallbackAddress {
                            Text("or \(fallback)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Pairing code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Self.grouped(remote.code))
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        Spacer(minLength: 4)
                        Button("New Code") { remote.newCode() }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                    }
                    HStack(spacing: 6) {
                        Text("Siri & Shortcuts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button(remote.isMakingShortcuts ? "Making…" : "Add Shortcuts…") { remote.addShortcuts() }
                            .buttonStyle(.glass)
                            .controlSize(.mini)
                            .disabled(remote.isMakingShortcuts || !remote.isListening)
                    }
                    if let status = remote.shortcutsStatus {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if remote.pairedCount > 0 {
                        HStack(spacing: 6) {
                            Text(remote.pairedCount == 1 ? "1 paired device" : "\(remote.pairedCount) paired devices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Button("Forget All") { remote.forgetPairedDevices() }
                                .buttonStyle(.glass)
                                .controlSize(.mini)
                        }
                    }
                }
                .padding(.leading, 8 + Metrics.badge + 12)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
        }
    }

    /// "123456" → "123 456", easier to read across a room.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}

/// Reset to Defaults, at the end of Settings, confirmed inline.
struct ResetRow: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "arrow.counterclockwise", isActive: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.confirmingReset ? "Reset Everything?" : "Reset to Defaults")
                    .font(.system(size: 13, weight: .medium))
                Text("Settings, dimming, and contrast to 50%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if controller.confirmingReset {
                Button("Cancel") { controller.cancelReset() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Button("Reset") { controller.resetToDefaults() }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(.small)
            } else {
                Button("Reset…") { controller.askToReset() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .animation(.snappy(duration: 0.2), value: controller.confirmingReset)
    }
}
