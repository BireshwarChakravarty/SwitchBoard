import AppKit

/// The menu-bar icon: the app icon's monitor, its screen half lit. Drawn in
/// code as a template image so macOS tints it like the system icons.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            NSColor.black.set()

            let screen = NSBezierPath(
                roundedRect: NSRect(x: 1.75, y: 1.25, width: 16.5, height: 10.5),
                xRadius: 2.2, yRadius: 2.2
            )
            screen.lineWidth = 1.5
            screen.stroke()

            // The lit half of the screen.
            NSBezierPath(
                roundedRect: NSRect(x: 3.5, y: 3, width: 6.5, height: 7),
                xRadius: 0.8, yRadius: 0.8
            ).fill()

            // Stand and base.
            NSBezierPath(rect: NSRect(x: 8.4, y: 11.75, width: 3.2, height: 2.2)).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 5.75, y: 13.6, width: 8.5, height: 1.6),
                xRadius: 0.8, yRadius: 0.8
            ).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Switchboard"
        return image
    }
}
