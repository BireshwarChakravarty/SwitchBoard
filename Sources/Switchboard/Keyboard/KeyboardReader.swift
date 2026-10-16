import AppKit
import IOKit.hid

/// Reads brightness keys straight from the keyboards (IOHIDManager).
///
/// On recent macOS, Apple keyboards' brightness keys (F1/F2 on a Magic
/// Keyboard) are handled inside the system's keyboard driver and never become
/// events an app can tap, so on a Mac mini they only produce the "not
/// supported" indicator. Reading the keyboard's own input reports sees them.
/// This needs Input Monitoring permission (Privacy & Security). It can only
/// listen, not swallow, so macOS may still show its own indicator.
///
/// Recognised:
/// - Consumer page Display Brightness Increment/Decrement (most keyboards).
/// - Apple top-case Brightness Up/Down (Apple keyboards).
/// - F1/F2 on Apple keyboards, following the "Use F1, F2, etc. as standard
///   function keys" setting and the fn key.
/// - F14/F15 (brightness keys on some extended keyboards).
@MainActor
final class KeyboardReader {
    /// A brightness key went down (`true`) or up (`false`).
    var onKey: (@MainActor (_ key: MediaKey, _ isDown: Bool) -> Void)?
    /// A key on a media page Switchboard doesn't use, for the status line.
    var onUnknown: (@MainActor (_ page: Int, _ usage: Int) -> Void)?

    private var manager: IOHIDManager?
    private var fnHeld = false

    var isRunning: Bool { manager != nil }

    static var hasPermission: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows macOS's Input Monitoring prompt if permission is missing.
    static func requestPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    @discardableResult
    func start() -> Bool {
        guard manager == nil else { return true }
        guard Self.hasPermission else { return false }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
            [kIOHIDDeviceUsagePageKey: kHIDPage_Consumer, kIOHIDDeviceUsageKey: kHIDUsage_Csmr_ConsumerControl]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let reader = Unmanaged<KeyboardReader>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            let page = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let pressed = IOHIDValueGetIntegerValue(value) != 0
            // Scheduled on the main run loop below.
            MainActor.assumeIsolated { reader.handle(page: page, usage: usage, pressed: pressed) }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            Log.app.notice("Keyboard reader: IOHIDManagerOpen failed: \(opened)")
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return false
        }
        self.manager = manager
        Log.app.info("Keyboard reader: listening")
        return true
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        fnHeld = false
        Log.app.info("Keyboard reader: stopped")
    }

    private func handle(page: Int, usage: Int, pressed: Bool) {
        if let key = Self.brightnessKey(page: page, usage: usage, fnHeld: fnHeld,
                                        standardFunctionKeys: Self.standardFunctionKeys) {
            Log.app.debug("Keyboard reader: page \(page) usage \(usage) \(pressed ? "down" : "up", privacy: .public)")
            onKey?(key, pressed)
            return
        }
        if page == Self.appleTopCasePage && usage == Self.topCaseFn {
            fnHeld = pressed
            return
        }
        if pressed && (page == kHIDPage_Consumer || page == Self.appleTopCasePage) {
            onUnknown?(page, usage)
        }
    }

    // MARK: Usage decoding (pure, unit-tested)

    static let appleTopCasePage = 0xFF
    static let topCaseFn = 0x03

    /// Whether "Use F1, F2, etc. keys as standard function keys" is on.
    static var standardFunctionKeys: Bool {
        UserDefaults.standard.bool(forKey: "com.apple.keyboard.fnState")
    }

    /// The brightness key a HID usage stands for, if any.
    nonisolated static func brightnessKey(page: Int, usage: Int, fnHeld: Bool, standardFunctionKeys: Bool) -> MediaKey? {
        switch (page, usage) {
        case (0x0C, 0x6F): return .brightnessUp      // Consumer: Display Brightness Increment
        case (0x0C, 0x70): return .brightnessDown    // Consumer: Display Brightness Decrement
        case (0xFF, 0x04): return .brightnessUp      // Apple top case: Brightness Up
        case (0xFF, 0x05): return .brightnessDown    // Apple top case: Brightness Down
        case (0x07, 0x69): return .brightnessDown    // Keyboard: F14
        case (0x07, 0x6A): return .brightnessUp      // Keyboard: F15
        case (0x07, 0x3A), (0x07, 0x3B):            // Keyboard: F1, F2
            // F1/F2 are brightness keys unless the user chose standard
            // function keys; fn flips that.
            let actsAsBrightness = standardFunctionKeys == fnHeld
            guard actsAsBrightness else { return nil }
            return usage == 0x3A ? .brightnessDown : .brightnessUp
        default:
            return nil
        }
    }
}
