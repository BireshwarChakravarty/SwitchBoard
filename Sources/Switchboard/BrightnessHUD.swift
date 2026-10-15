import AppKit
import SwiftUI

/// The on-screen brightness indicator shown when a brightness key is pressed:
/// a Liquid Glass capsule with a sun and a 16-step level bar, top right of
/// the screen, fading out shortly after the last press, like the system's own.
@MainActor
final class BrightnessHUD {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    private static let size = NSSize(width: 240, height: 52)

    /// Show `level` (0...1) on the screen showing `displayID`.
    func show(level: Double, on displayID: CGDirectDisplayID) {
        model.level = min(max(level, 0), 1)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let frame = Self.screen(for: displayID)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: frame.maxX - Self.size.width - 12,
                y: frame.maxY - Self.size.height - 12
            ))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the glass draws its own
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        panel.contentView = hosting
        return panel
    }

    /// The NSScreen showing this display (for a mirror, the screen it mirrors).
    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let mirrored = CGDisplayMirrorsDisplay(displayID)
        let candidates = [displayID, mirrored].filter { $0 != 0 }
        for id in candidates {
            if let screen = NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }) {
                return screen
            }
        }
        return NSScreen.main
    }
}

private final class HUDModel: ObservableObject {
    @Published var level: Double = 0
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.level < 0.01 ? "sun.min" : "sun.max.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 20)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.primary)
                        .frame(width: max(0, geometry.size.width * model.level))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 18)
        .frame(width: 240, height: 52)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.15), value: model.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Brightness \(Int((model.level * 100).rounded())) percent"))
    }
}
