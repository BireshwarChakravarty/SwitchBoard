import SwiftUI
import AppKit

/// The menu: every screen, the selected one opened with its controls, then
/// Settings and Quit as menu items.
struct MenuContent: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ScreenList(controller: controller)
            if let level = controller.allScreensBrightness {
                AllScreensCard(level: level, controller: controller)
            }
            if controller.brightnessKeysNeedPermission || controller.inputMonitoringNeeded {
                PermissionBanner(controller: controller)
            }
            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            VStack(spacing: 0) {
                MenuRowButton(title: "Settings…", key: ",") {
                    SettingsWindow.shared.show(controller: controller)
                }
                MenuRowButton(title: "Quit Switchboard", key: "q") {
                    // Never leave a screen disconnected or dimmed behind us.
                    controller.prepareToQuit()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(8)
        .frame(width: Metrics.width)
        .tint(Theme.signal)
        .onAppear { controller.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Screens")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if controller.displays.count > 1 {
                Text("\(controller.displays.count) connected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

/// One brightness slider for every adjustable screen.
struct AllScreensCard: View {
    let level: Double
    @ObservedObject var controller: DisplayController

    var body: some View {
        ControlBlock(title: "All Screens", value: "\(Int((level * 100).rounded()))%") {
            LevelSlider(value: level) { controller.setAllScreensBrightness($0) }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
        )
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
                    .font(.system(size: 12, weight: .medium))
                Text("Open Settings to see what macOS needs.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Settings…") { SettingsWindow.shared.show(controller: controller, pane: .keyboard) }
                .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Theme.card)
        )
    }
}
