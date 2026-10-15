import Foundation
import CoreGraphics
import Combine
import AppKit

/// One display macOS currently sees (or one we switched off that has since
/// dropped off the display list).
struct ManagedDisplay: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    /// Our last-known intent. macOS can't read true DDC power back reliably on
    /// all monitors, so this reflects what this app last set.
    var isOn: Bool
    var offMethod: OffMethod = .standby
    /// Whether the row shows an on/off switch (a per-monitor choice).
    var showsSwitch = true
    /// Switch off when the screen locks or the Mac sleeps, on at unlock/wake.
    var autoOff = false
    /// Why the last attempt failed, shown under the name.
    var problem: String?
    /// "Mirrored to <screen>" / "Mirror of <screen>".
    var mirrorNote: String?
    /// Hardware controls the monitor reported over DDC/CI (nil = unavailable).
    var brightness: VCPValue?
    var contrast: VCPValue?
    var volume: VCPValue?
    /// Software dimming level (0 = black, 1 = normal), offered when the
    /// monitor's brightness can't be set over DDC/CI.
    var dimLevel: Double?

    /// Only external monitors can be switched (DDC or disconnect).
    var canToggle: Bool { !isBuiltIn }
}

/// Enumerates displays, switches them off/on, drives brightness/contrast/
/// volume and software dimming, and republishes the list when displays are
/// attached/detached.
@MainActor
final class DisplayController: ObservableObject {
    @Published private(set) var displays: [ManagedDisplay] = []
    @Published private(set) var launchAtLogin = LoginItem.isEnabled
    @Published private(set) var brightnessKeysEnabled = Preferences.brightnessKeysEnabled
    /// Brightness keys are on but macOS hasn't granted Accessibility yet.
    @Published private(set) var brightnessKeysNeedPermission = false
    /// Reset to Defaults was clicked and awaits confirmation.
    @Published private(set) var confirmingReset = false

    private let ddc = DDC.makeController()
    /// All DDC traffic goes through this queue: it's slow, and one message at
    /// a time keeps the bus happy.
    private let ddcQueue = DispatchQueue(label: "Switchboard.ddc")
    private let dimmer = SoftwareDimmer()
    private let keys = BrightnessKeys()
    private let hud = BrightnessHUD()
    private var permissionTimer: Timer?
    private var didPromptForAccessibility = false

    private var intents: [CGDirectDisplayID: Bool] = [:]
    /// Last identity seen for every external display, kept after it goes offline.
    private var identities: [CGDirectDisplayID: DisplayIdentity] = [:]
    private var problems: [CGDirectDisplayID: String] = [:]
    /// Names looked up from the IORegistry, for displays NSScreen doesn't name.
    private var registryNames: [CGDirectDisplayID: String] = [:]

    /// DDC values read from each monitor (an empty dictionary once read but
    /// nothing answered), and the monitors being read right now.
    private var ddcValues: [CGDirectDisplayID: [UInt8: VCPValue]] = [:]
    private var probing: Set<CGDirectDisplayID> = []

    /// Slider moves arrive faster than DDC can carry them: keep only the
    /// latest value per control and send it when the previous write is done.
    private struct WriteKey: Hashable {
        let id: CGDirectDisplayID
        let vcp: UInt8
    }
    private var pendingWrites: [WriteKey: UInt16] = [:]
    private var writesInFlight: Set<WriteKey> = []

    private var isLocked = false
    /// Monitors switched off by lock/sleep, to switch back on afterwards.
    private var autoSwitchedOff: Set<CGDirectDisplayID> = []

    init() {
        LoginItem.enableOnFirstInstalledLaunch()
        // A previous run may have quit or crashed with a screen disconnected:
        // bring it back so it can never get stuck off.
        reconnectAll()
        keys.canHandle = { [weak self] id in self?.canAdjustBrightness(on: id) ?? false }
        keys.onPress = { [weak self] up, fine, id in self?.adjustBrightness(up: up, fine: fine, on: id) }
        refresh()
        CGDisplayRegisterReconfigurationCallback({ _, _, userInfo in
            guard let userInfo else { return }
            let controller = Unmanaged<DisplayController>
                .fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in controller.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        observeSystemEvents()
    }

    func refresh() {
        let ids = Displays.online()
        let mainID = CGMainDisplayID()

        var list = ids.map { id -> ManagedDisplay in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let displayName = name(for: id)
            if !isBuiltIn {
                identities[id] = DisplayIdentity(id: id, name: displayName)
            }
            return makeDisplay(id: id, name: displayName, isBuiltIn: isBuiltIn, isMain: id == mainID)
        }

        // A switched-off monitor can drop off the display list (disconnected
        // in software, or one that stops signalling "connected" in standby).
        // Keep a row for it so it can be switched back on.
        for (id, isOn) in intents where !isOn && !ids.contains(id) {
            guard let identity = identities[id] else { continue }
            list.append(makeDisplay(id: id, name: identity.name, isBuiltIn: false, isMain: false))
        }

        // Describe mirroring: "Mirrored to …" on the source, "Mirror of …" on copies.
        let names = Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for index in list.indices {
            let id = list[index].id
            let primary = CGDisplayMirrorsDisplay(id)
            if primary != 0, let primaryName = names[primary] {
                list[index].mirrorNote = "Mirror of \(primaryName)"
            } else {
                let mirrors = list.filter { CGDisplayMirrorsDisplay($0.id) == id }.map(\.name)
                if !mirrors.isEmpty {
                    list[index].mirrorNote = "Mirrored to " + mirrors.joined(separator: ", ")
                }
            }
        }

        // The last screen still on gets no switch, so every screen can never
        // be switched off at once.
        if list.filter(\.isOn).count <= 1 {
            for index in list.indices where list[index].isOn {
                list[index].showsSwitch = false
            }
        }

        // External displays first, built-in last.
        displays = list.sorted {
            ($0.isBuiltIn ? 1 : 0, $0.name) < ($1.isBuiltIn ? 1 : 0, $1.name)
        }
        launchAtLogin = LoginItem.isEnabled
        // macOS resets gamma tables when displays are reconfigured.
        dimmer.reapplyAll()
        probeDDC()
        syncBrightnessKeys()
    }

    private func makeDisplay(id: CGDirectDisplayID, name: String, isBuiltIn: Bool, isMain: Bool) -> ManagedDisplay {
        var display = ManagedDisplay(
            id: id, name: name, isBuiltIn: isBuiltIn, isMain: isMain,
            isOn: intents[id] ?? true // assume on until we switch it
        )
        display.problem = problems[id]
        guard !isBuiltIn, let key = identities[id]?.key else { return display }

        display.offMethod = Preferences.offMethod(for: key)
        display.showsSwitch = Preferences.switchVisible(for: key) ?? true
        display.autoOff = Preferences.autoOff(for: key)

        if display.offMethod == .disconnect {
            // No DDC/CI on this monitor: dim it in software instead.
            display.dimLevel = dimmer.level(for: id)
        } else if let values = ddcValues[id] {
            display.brightness = values[VCP.brightness]
            display.contrast = values[VCP.contrast]
            display.volume = values[VCP.volume]
            if display.brightness == nil { display.dimLevel = dimmer.level(for: id) }
        }
        return display
    }

    private func updateRow(_ id: CGDirectDisplayID, _ change: (inout ManagedDisplay) -> Void) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        change(&displays[index])
    }

    // MARK: Switching

    func setPower(on: Bool, for id: CGDirectDisplayID) {
        guard let display = displays.first(where: { $0.id == id }), display.canToggle,
              let identity = identities[id] else { return }
        problems[id] = nil
        if on {
            switchOn(identity)
        } else {
            switchOff(identity)
        }
        refresh()
    }

    private func switchOff(_ identity: DisplayIdentity) {
        let id = identity.id
        if Preferences.offMethod(for: identity.key) == .standby {
            if ddcSync({ $0.setPower(.standby, for: identity) }) {
                intents[id] = false
                return
            }
            // No answer over DDC/CI (unsupported or disabled on the monitor):
            // switch this monitor off by disconnecting it, now and from now on.
            Log.display.notice("\(identity.name, privacy: .public) did not answer DDC/CI; switching it off by disconnecting")
            Preferences.setOffMethod(.disconnect, for: identity.key)
        }
        disconnect(identity)
    }

    private func switchOn(_ identity: DisplayIdentity) {
        let id = identity.id
        if Preferences.disconnectedDisplays.contains(id) {
            if SoftwareDisconnect.setEnabled(true, displayID: id) {
                Preferences.disconnectedDisplays.remove(id)
                intents[id] = true
            } else {
                problems[id] = "Couldn't reconnect"
            }
        } else if ddcSync({ $0.setPower(.on, for: identity) }) {
            intents[id] = true
        } else {
            problems[id] = "Not responding to DDC/CI"
        }
    }

    private func disconnect(_ identity: DisplayIdentity) {
        let id = identity.id
        guard !isLastActiveDisplay(id) else {
            problems[id] = "Can't disconnect the only active screen"
            return
        }
        if SoftwareDisconnect.setEnabled(false, displayID: id) {
            Preferences.disconnectedDisplays.insert(id)
            intents[id] = false
        } else {
            problems[id] = "Couldn't disconnect"
        }
    }

    private func isLastActiveDisplay(_ id: CGDirectDisplayID) -> Bool {
        let active = Displays.active()
        return active.count <= 1 && active.contains(id)
    }

    /// Reconnect every display this app disconnected in software.
    func reconnectAll() {
        for id in Preferences.disconnectedDisplays {
            SoftwareDisconnect.setEnabled(true, displayID: id)
            intents[id] = nil
        }
        Preferences.disconnectedDisplays = []
    }

    /// Put every screen back to normal before the app quits.
    func prepareToQuit() {
        reconnectAll()
        dimmer.restoreAll()
    }

    // MARK: Brightness, contrast, volume (DDC)

    /// Read brightness/contrast/volume once from each DDC monitor, in the background.
    private func probeDDC() {
        for display in displays where display.canToggle && display.isOn && display.offMethod == .standby {
            let id = display.id
            guard ddcValues[id] == nil, !probing.contains(id), let identity = identities[id] else { continue }
            probing.insert(id)
            let ddc = self.ddc
            ddcQueue.async {
                var values: [UInt8: VCPValue] = [:]
                for vcp in [VCP.brightness, VCP.contrast, VCP.volume] {
                    if let value = ddc.read(vcp, for: identity) { values[vcp] = value }
                }
                let result = values
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.probing.remove(id)
                    self.ddcValues[id] = result
                    self.refresh()
                }
            }
        }
    }

    /// Set a DDC control (from a slider or a brightness key).
    func setVCP(_ vcp: UInt8, to value: UInt16, for id: CGDirectDisplayID) {
        guard var values = ddcValues[id], var control = values[vcp] else { return }
        control.current = min(value, control.max)
        values[vcp] = control
        ddcValues[id] = values
        updateRow(id) { row in
            switch vcp {
            case VCP.brightness: row.brightness = control
            case VCP.contrast: row.contrast = control
            case VCP.volume: row.volume = control
            default: break
            }
        }
        let key = WriteKey(id: id, vcp: vcp)
        pendingWrites[key] = control.current
        pumpWrites(key)
    }

    private func pumpWrites(_ key: WriteKey) {
        guard !writesInFlight.contains(key),
              let value = pendingWrites.removeValue(forKey: key),
              let identity = identities[key.id] else { return }
        writesInFlight.insert(key)
        let ddc = self.ddc
        ddcQueue.async {
            let ok = ddc.write(key.vcp, value: value, for: identity)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.writesInFlight.remove(key)
                if !ok {
                    self.problems[key.id] = "Not responding to DDC/CI"
                    self.updateRow(key.id) { $0.problem = "Not responding to DDC/CI" }
                }
                self.pumpWrites(key)
            }
        }
    }

    // MARK: Software dimming

    func setDimLevel(_ level: Double, for id: CGDirectDisplayID) {
        dimmer.setLevel(level, for: id)
        let applied = dimmer.level(for: id)
        updateRow(id) { $0.dimLevel = applied }
    }

    // MARK: Brightness keys

    func setBrightnessKeysEnabled(_ enabled: Bool) {
        Preferences.brightnessKeysEnabled = enabled
        brightnessKeysEnabled = enabled
        if enabled && !BrightnessKeys.hasPermission {
            BrightnessKeys.requestPermission()
        }
        syncBrightnessKeys()
    }

    /// Start or stop the key tap to match the setting. Until Accessibility is
    /// granted the tap can't start: ask once per launch, then keep retrying
    /// quietly every couple of seconds so the keys work as soon as it's granted.
    private func syncBrightnessKeys() {
        if brightnessKeysEnabled {
            if !keys.isRunning {
                if !BrightnessKeys.hasPermission && !didPromptForAccessibility {
                    didPromptForAccessibility = true
                    BrightnessKeys.requestPermission()
                }
                keys.start()
            }
        } else {
            keys.stop()
        }
        let waiting = brightnessKeysEnabled && !keys.isRunning
        if brightnessKeysNeedPermission != waiting { brightnessKeysNeedPermission = waiting }
        if waiting, permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncBrightnessKeys() }
            }
        } else if !waiting {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    /// Screens in the same mirror set show the same picture and are adjusted together.
    private func mirrorSet(of id: CGDirectDisplayID) -> [ManagedDisplay] {
        func primary(_ id: CGDirectDisplayID) -> CGDirectDisplayID {
            let mirrored = CGDisplayMirrorsDisplay(id)
            return mirrored == 0 ? id : mirrored
        }
        let set = primary(id)
        return displays.filter { primary($0.id) == set }
    }

    private func isAdjustable(_ display: ManagedDisplay) -> Bool {
        display.isOn && !display.isBuiltIn && (display.brightness != nil || display.dimLevel != nil)
    }

    /// The screens a brightness key aimed at `id` adjusts: that screen and its
    /// mirrors, or, if none of them can be adjusted, every adjustable screen,
    /// so a key press never does nothing.
    private func brightnessTargets(for id: CGDirectDisplayID) -> [ManagedDisplay] {
        let pointed = mirrorSet(of: id).filter { isAdjustable($0) }
        return pointed.isEmpty ? displays.filter { isAdjustable($0) } : pointed
    }

    private func canAdjustBrightness(on id: CGDirectDisplayID) -> Bool {
        !brightnessTargets(for: id).isEmpty
    }

    /// One brightness-key press (or auto-repeat).
    private func adjustBrightness(up: Bool, fine: Bool, on id: CGDirectDisplayID) {
        let targets = brightnessTargets(for: id)
        var shown: Double?
        for display in targets {
            let level = adjustBrightness(up: up, fine: fine, of: display)
            if shown == nil { shown = level }
        }
        if let shown, let first = targets.first {
            hud.show(level: shown, on: first.id)
        }
    }

    /// Step one screen's brightness on a 16-step scale (64 with ⇧⌥), like
    /// the system does, and return the new level (0...1).
    private func adjustBrightness(up: Bool, fine: Bool, of display: ManagedDisplay) -> Double? {
        let steps = fine ? 64.0 : 16.0
        func stepped(_ level: Double) -> Double {
            let next = ((level * steps).rounded() + (up ? 1 : -1)) / steps
            return min(max(next, 0), 1)
        }
        if let brightness = display.brightness {
            let level = stepped(Double(brightness.current) / Double(brightness.max))
            setVCP(VCP.brightness, to: UInt16((level * Double(brightness.max)).rounded()), for: display.id)
            return level
        }
        if let current = display.dimLevel {
            let level = stepped(current)
            setDimLevel(level, for: display.id)
            return level
        }
        return nil
    }

    // MARK: Lock / sleep automation

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoSwitch(on: false) }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // If the screen is locked, wait for the unlock instead.
                guard let self, !self.isLocked else { return }
                self.autoSwitch(on: true)
            }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dimmer.reapplyAll() }
        }

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = true
                self?.autoSwitch(on: false)
            }
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = false
                self?.autoSwitch(on: true)
            }
        }
    }

    private func autoSwitch(on: Bool) {
        if on {
            let ids = autoSwitchedOff
            autoSwitchedOff = []
            for id in ids { setPower(on: true, for: id) }
        } else {
            for display in displays where display.canToggle && display.isOn && display.autoOff {
                setPower(on: false, for: display.id)
                if intents[display.id] == false { autoSwitchedOff.insert(display.id) }
            }
        }
    }

    // MARK: Reset to Defaults

    func askToReset() { confirmingReset = true }
    func cancelReset() { confirmingReset = false }

    /// Put every screen back to normal and forget all settings.
    func resetToDefaults() {
        confirmingReset = false
        keys.stop()
        dimmer.restoreAll()
        // Wake monitors this app put in standby, reconnect disconnected ones.
        for (id, isOn) in intents where !isOn {
            guard let identity = identities[id],
                  !Preferences.disconnectedDisplays.contains(id) else { continue }
            _ = ddcSync { $0.setPower(.on, for: identity) }
        }
        reconnectAll()
        Preferences.resetAll()
        intents = [:]
        problems = [:]
        ddcValues = [:]
        autoSwitchedOff = []
        brightnessKeysEnabled = Preferences.brightnessKeysEnabled
        if LoginItem.isAvailable { LoginItem.setEnabled(true) }
        refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Per-monitor settings

    func setSwitchVisible(_ visible: Bool, for id: CGDirectDisplayID) {
        guard let key = identities[id]?.key else { return }
        Preferences.setSwitchVisible(visible, for: key)
        refresh()
    }

    func setOffMethod(_ method: OffMethod, for id: CGDirectDisplayID) {
        guard let key = identities[id]?.key else { return }
        Preferences.setOffMethod(method, for: key)
        refresh()
    }

    func setAutoOff(_ enabled: Bool, for id: CGDirectDisplayID) {
        guard let key = identities[id]?.key else { return }
        Preferences.setAutoOff(enabled, for: key)
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        LoginItem.setEnabled(enabled)
        launchAtLogin = LoginItem.isEnabled
    }

    // MARK: Helpers

    /// Run a DDC operation on the DDC queue and wait for it (power switching,
    /// where the UI needs the answer).
    private func ddcSync<T>(_ work: (DDCController) -> T) -> T {
        let ddc = self.ddc
        return ddcQueue.sync { work(ddc) }
    }

    /// The monitor's human-readable name, as macOS or its EDID reports it.
    private func name(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber, number.uint32Value == id {
                let localized = screen.localizedName
                if !localized.isEmpty { return localized }
            }
        }
        guard CGDisplayIsBuiltin(id) == 0 else { return "Built-in Display" }
        // NSScreen has no entry for some displays (mirrored or disconnected
        // ones): ask the DDC transport, which reads the monitor's EDID name.
        if let cached = registryNames[id] { return cached }
        if let registryName = ddcSync({ $0.productName(for: id) }) {
            registryNames[id] = registryName
            return registryName
        }
        if let known = identities[id]?.name { return known }
        // Fallback to the EDID-derived vendor/model numbers if no name is exposed.
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        if vendor != 0 || model != 0 {
            return String(format: "Display %04X:%04X", vendor, model)
        }
        return "Display \(id)"
    }
}
