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
