import AppKit
import ApplicationServices

/// Makes the keyboard's brightness keys adjust the external screen under the
/// pointer.
///
/// macOS applies brightness keys only to built-in and Apple displays, so we
/// intercept them with an event tap. Keys aimed at a screen we don't control
/// (such as a MacBook's built-in display) pass through to macOS untouched.
/// Taps that swallow events need Accessibility permission (System Settings →
/// Privacy & Security → Accessibility).
@MainActor
final class BrightnessKeys {
    /// Whether we handle keys aimed at this screen; if not, macOS gets them.
    var canHandle: (@MainActor (_ displayID: CGDirectDisplayID) -> Bool)?
    /// Called on each key press: `up` is true for brightness up.
    var onPress: (@MainActor (_ up: Bool, _ displayID: CGDirectDisplayID) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "allow Accessibility" prompt if permission is missing.
    static func requestPermission() {
        // The value of kAXTrustedCheckOptionPrompt, whose Swift type differs
        // between SDK versions.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Starts intercepting. Returns false if macOS refused (no permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        // NX_SYSDEFINED (14) carries the media and brightness keys.
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let keys = Unmanaged<BrightnessKeys>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap's run-loop source is on the main run loop.
                let swallow = MainActor.assumeIsolated { keys.handle(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
    }

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        // 14 = NX_SYSDEFINED; subtype 8 = auxiliary control buttons.
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return false }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let isKeyDown = ((data & 0xFF00) >> 8) == 0x0A
        let up: Bool
        switch keyCode {
        case 2: up = true   // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: up = false  // NX_KEYTYPE_BRIGHTNESS_DOWN
        default: return false // volume, play/pause etc.: leave to macOS
        }
        guard let displayID = Self.displayUnderPointer(),
              canHandle?(displayID) == true else { return false }
        if isKeyDown {
            onPress?(up, displayID)
        }
        return true // swallow key-down and key-up alike
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &displayID, &count) == .success, count > 0 else {
            return nil
        }
        return displayID
    }
}
