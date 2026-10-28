import SwiftUI
import AppKit

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
                    if controller.brightnessKeysNeedPermission || controller.inputMonitoringNeeded {
                        PermissionBanner(controller: controller)
                    }
                }
            }
            Footer(controller: controller)
        }
        .padding(12)
        .frame(width: Metrics.width)
        .onAppear { controller.refresh() }
    }
}

struct Footer: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Switchboard")
                    .font(.subheadline.weight(.semibold))
                Text(controller.versionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CircleButton(icon: "gearshape", help: "Settings…") {
                SettingsWindow.shared.show(controller: controller)
            }
            .keyboardShortcut(",")
            CircleButton(icon: "power", help: "Quit Switchboard") {
                // Never leave a screen disconnected or dimmed behind us.
                controller.prepareToQuit()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 6)
    }
}

/// Shown when the keyboard keys are on but macOS hasn't granted the access
/// they need. Settings explains which, with links to Privacy & Security.
struct PermissionBanner: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Keyboard Keys Need Access")
                    .font(.subheadline.weight(.medium))
                Text("Open Settings to see what macOS needs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Settings…") { SettingsWindow.shared.show(controller: controller) }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
    }
}
