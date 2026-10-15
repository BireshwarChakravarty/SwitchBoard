import AppKit
import ApplicationServices

/// The keyboard keys Switchboard can take over.
enum MediaKey {
    case brightnessUp, brightnessDown
    case volumeUp, volumeDown, mute

    var isBrightness: Bool { self == .brightnessUp || self == .brightnessDown }
}

/// Makes the keyboard's brightness keys (and, for monitor speakers, the
/// volume keys) control the monitors.
///
/// A Mac mini has no screen of its own, so macOS ignores brightness keys
/// ("not supported"), and it can't set the volume of a monitor's speakers.
/// We intercept those keys with an event tap, which needs Accessibility
/// permission (System Settings → Privacy & Security → Accessibility). Keys we
/// can't act on pass through to macOS untouched.
@MainActor
final class MediaKeys {
    /// Whether we act on this key aimed at this screen; if not, macOS gets it.
    var canHandle: (@MainActor (_ key: MediaKey, _ displayID: CGDirectDisplayID) -> Bool)?
    /// Called on each press (and auto-repeat, except for mute). `fine` is
    /// true with ⇧⌥ held, for quarter steps.
    var onPress: (@MainActor (_ key: MediaKey, _ fine: Bool, _ displayID: CGDirectDisplayID) -> Void)?
    /// Called for every media-key press the tap sees, with its raw key code
    /// (nil `key` for keys Switchboard doesn't use), for the status line.
    var onSeen: (@MainActor (_ key: MediaKey?, _ code: Int) -> Void)?

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
        // NX_SYSDEFINED (14) carries the media, volume and brightness keys;
        // key down/up catch F14/F15, which are brightness keys on some keyboards.
        let mask = CGEventMask(1 << 14)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let keys = Unmanaged<MediaKeys>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap's run-loop source is on the main run loop.
                let swallow = MainActor.assumeIsolated { keys.handle(type: type, event: event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.app.notice("Keys: event tap refused (Accessibility permission missing)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        Log.app.info("Keys: listening")
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.source = nil
        Log.app.info("Keys: stopped")
    }

    /// Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disables a tap that was too slow; turn it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard let press = Self.decode(type: type, event: event) else { return false }
        let key = press.key
        if press.isKeyDown && !press.isRepeat {
            onSeen?(key, press.code)
        }
        guard let key else { return false }

        let displayID = Self.displayUnderPointer() ?? CGMainDisplayID()
        guard canHandle?(key, displayID) == true else {
            if key.isBrightness {
                Log.app.notice("Brightness key: no adjustable screen yet, passing to macOS")
            }
            return false
        }
        if press.isKeyDown && !(key == .mute && press.isRepeat) {
            Log.app.debug("Key \(String(describing: key), privacy: .public)\(press.fine ? " (fine)" : "", privacy: .public) on display \(displayID)")
            onPress?(key, press.fine, displayID)
        }
        return true // swallow key-down and key-up alike, so macOS shows no "not supported" HUD
    }

    private struct Press {
        let key: MediaKey?
        let code: Int
        let isKeyDown: Bool
        let isRepeat: Bool
        let fine: Bool
    }

    /// Decode a media-key event (NX_SYSDEFINED) or an F14/F15 key event.
    /// Returns nil for anything else, which passes straight through.
    private static func decode(type: CGEventType, event: CGEvent) -> Press? {
        if type == .keyDown || type == .keyUp {
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let key: MediaKey
            switch code {
            case 107: key = .brightnessDown  // F14
            case 113: key = .brightnessUp    // F15
            default: return nil
            }
            return Press(
                key: key, code: code, isKeyDown: type == .keyDown,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                fine: event.flags.contains([.maskShift, .maskAlternate])
            )
        }

        // 14 = NX_SYSDEFINED; subtype 8 = auxiliary control buttons.
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return nil }
        let data = nsEvent.data1
        let code = (data & 0xFFFF_0000) >> 16
        let key: MediaKey?
        switch code {
        case 0: key = .volumeUp        // NX_KEYTYPE_SOUND_UP
        case 1: key = .volumeDown      // NX_KEYTYPE_SOUND_DOWN
        case 2: key = .brightnessUp    // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown  // NX_KEYTYPE_BRIGHTNESS_DOWN
        case 7: key = .mute            // NX_KEYTYPE_MUTE
        default: key = nil             // play/pause etc.: leave to macOS
        }
        return Press(
            key: key, code: code,
            isKeyDown: ((data & 0xFF00) >> 8) == 0x0A,
            isRepeat: (data & 0x1) != 0,
            fine: nsEvent.modifierFlags.contains([.shift, .option])
        )
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
