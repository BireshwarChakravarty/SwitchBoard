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
    /// Combined brightness (0...1): the DDC backlight with software dimming
    /// below it, or software dimming alone (see BrightnessCurve). Nil when
    /// the screen can't be adjusted.
    var combinedBrightness: Double?
    /// Scaled resolutions and the selected one. Empty for mirrors, which
    /// follow the screen they mirror.
    var resolutions: [Resolution] = []
    var resolutionIndex: Int?

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
    /// Brightness keys are on but macOS hasn't granted Input Monitoring yet
    /// (needed to read Apple keyboards' brightness keys).
    @Published private(set) var inputMonitoringNeeded = false
    /// What the keyboard keys are doing, shown under Keyboard Keys, e.g.
    /// "Listening · press a brightness key" or "Brightness Up → DELL U2723QE · 65%".
    @Published private(set) var keysStatus: String?
    /// Brightness follows Light/Dark mode (see Preferences.brightnessFollowsAppearance).
    @Published private(set) var brightnessFollowsAppearance = Preferences.brightnessFollowsAppearance
    /// The screen whose controls the menu shows (nil: pick a sensible one).
    @Published private(set) var selectedDisplayID: CGDirectDisplayID?
    /// Whether the Settings section of the menu is expanded.
    @Published private(set) var settingsExpanded = false
    /// Reset to Defaults was clicked and awaits confirmation.
    @Published private(set) var confirmingReset = false

    private let ddc = DDC.makeController()
    /// All DDC traffic goes through this queue: it's slow, and one message at
    /// a time keeps the bus happy.
    private let ddcQueue = DispatchQueue(label: "Switchboard.ddc")
    private let dimmer = SoftwareDimmer()
    private let keys = MediaKeys()
    private let keyboard = KeyboardReader()
    /// Brightness key currently held on the keyboard, and its repeat timer.
    private var heldKey: MediaKey?
    private var repeatTimer: Timer?
    /// When each brightness key last stepped, so one press reported by two
    /// sources (event tap and keyboard reader) counts once.
    private var lastStep: [MediaKey: Date] = [:]
    private var didPromptForInputMonitoring = false
    private let hud = LevelHUD()
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

    /// Display modes behind each screen's resolution slider, the position
    /// being dragged to, and the volume to restore when unmuting.
    private var displayModes: [CGDirectDisplayID: [CGDisplayMode]] = [:]
    private var resolutionCache: [CGDirectDisplayID: (resolutions: [Resolution], current: Int)] = [:]
    private var refreshTask: Task<Void, Never>?
    private var resolutionPreview: [CGDirectDisplayID: Int] = [:]
    private var mutedVolume: [CGDirectDisplayID: UInt16] = [:]

    private var isLocked = false
    /// Monitors switched off by lock/sleep, to switch back on afterwards.
    private var autoSwitchedOff: Set<CGDirectDisplayID> = []

    init() {
        LoginItem.enableOnFirstInstalledLaunch()
        // A previous run (or an older version) may have left a screen
        // disconnected: bring it back so it can never get stuck off.
        reconnectAll(scope: .session)
        keys.canHandle = { [weak self] key, id in self?.canHandle(key, on: id) ?? false }
        keys.onPress = { [weak self] key, fine, id in self?.handle(key, fine: fine, on: id) }
        keys.onSeen = { [weak self] key, code in self?.keySeen(key, code: code) }
        keyboard.onKey = { [weak self] key, isDown in self?.keyboardKey(key, isDown: isDown) }
        keyboard.onUnknown = { [weak self] page, usage in
            self?.keysStatus = String(format: "Received key 0x%02X/0x%02X, which Switchboard doesn't use", page, usage)
        }
        refresh()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            // Ignore the "about to reconfigure" call; react once it's done.
            guard let userInfo, !flags.contains(.beginConfigurationFlag) else { return }
            let controller = Unmanaged<DisplayController>
                .fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in controller.scheduleRefresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        observeSystemEvents()
        applyAppearanceBrightness()
    }

    /// Re-read everything: the screen list, resolutions, gamma, DDC values.
    func refresh() {
        rebuild(heavy: true)
    }

    /// After macOS reconfigures displays (a screen switched on or off, a
    /// resolution changed), it keeps adjusting them for a moment and fires
    /// several callbacks. Querying display modes, rewriting gamma tables or
    /// talking DDC during that can prolong the blank on other screens, so wait
    /// until it has settled and refresh once.
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Rebuild the screen list. `heavy: false` only updates rows from what's
    /// already known (no display-mode queries, gamma writes or DDC), for use
    /// right after a change while macOS is still reconfiguring.
    private func rebuild(heavy: Bool) {
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

        // Resolutions, for screens that aren't mirrors of another.
        if heavy {
            for id in ids {
                guard CGDisplayMirrorsDisplay(id) == 0, let available = DisplayModes.available(for: id) else {
                    displayModes[id] = nil
                    resolutionCache[id] = nil
                    continue
                }
                displayModes[id] = available.modes
                resolutionCache[id] = (available.modes.map(DisplayModes.resolution(of:)), available.current)
            }
        }
        for index in list.indices {
            let id = list[index].id
            guard ids.contains(id), let cached = resolutionCache[id] else { continue }
            list[index].resolutions = cached.resolutions
            list[index].resolutionIndex = resolutionPreview[id] ?? cached.current
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
        guard heavy else { return }
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

        if display.offMethod != .standby {
            // No DDC/CI on this monitor: software dimming only.
            display.combinedBrightness = combinedLevel(of: id, hardware: nil)
        } else if let values = ddcValues[id] {
            display.brightness = values[VCP.brightness]
            display.contrast = values[VCP.contrast]
            display.volume = values[VCP.volume]
            display.combinedBrightness = combinedLevel(of: id, hardware: display.brightness)
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
        // Update the rows now; the full refresh follows once macOS settles.
        rebuild(heavy: false)
        scheduleRefresh()
    }

    private func switchOff(_ identity: DisplayIdentity) {
        let id = identity.id
        let key = identity.key
        var method = Preferences.offMethod(for: key)
        if method == .standby {
            if ddcSync({ $0.setPower(.standby, for: identity) }) {
                intents[id] = false
                return
            }
            // No answer over DDC/CI (unsupported or disabled on the monitor):
            // switch it off by disconnecting, now and from now on.
            method = .disconnect
            Log.display.notice("\(identity.name, privacy: .public) did not answer DDC/CI; switching it off by disconnecting")
            Preferences.setOffMethod(method, for: key, automatic: true)
        } else if method == .blackout, Preferences.offMethodIsAutomatic(for: key) {
            // An earlier version picked Black Out on its own. Only a user's
            // explicit choice should black a screen out.
            method = .disconnect
            Preferences.setOffMethod(method, for: key, automatic: true)
        }

        switch method {
        case .blackout:
            if !blackOut(identity) {
                Preferences.setOffMethod(.disconnect, for: key, automatic: true)
                disconnect(identity)
            }
        case .disconnect, .standby:
            disconnect(identity)
        }
    }

    /// Turn the screen's picture black. Fails (and undoes it) if another
    /// screen went black too, which happens when screens share a gamma table.
    private func blackOut(_ identity: DisplayIdentity) -> Bool {
        let id = identity.id
        let others = Displays.online().filter { $0 != id && !dimmer.isBlackedOut($0) }
        let alreadyBlack = Set(others.filter { SoftwareDimmer.looksBlack($0) })
        dimmer.setBlackedOut(true, for: id)
        if others.contains(where: { !alreadyBlack.contains($0) && SoftwareDimmer.looksBlack($0) }) {
            Log.display.notice("Blacking out \(identity.name, privacy: .public) also blacked out another screen; disconnecting instead")
            dimmer.setBlackedOut(false, for: id)
            return false
        }
        intents[id] = false
        return true
    }

    private func switchOn(_ identity: DisplayIdentity) {
        let id = identity.id
        if dimmer.isBlackedOut(id) {
            dimmer.setBlackedOut(false, for: id)
            intents[id] = true
        } else if Preferences.disconnectedDisplays.contains(id) {
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
    /// `scope: .session` also undoes session-wide disconnects left by older
    /// versions (used at launch); disconnects made by this version are
    /// app-only and macOS undoes them itself when the app quits.
    func reconnectAll(scope: SoftwareDisconnect.Scope = .app) {
        for id in Preferences.disconnectedDisplays {
            SoftwareDisconnect.setEnabled(true, displayID: id, scope: scope)
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
                    // Now that its brightness is known, bring it to this mode's level.
                    self.applyAppearanceBrightness(to: id)
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

    /// Ask the monitor to restore its factory brightness and contrast (or,
    /// with `everything`, all its factory settings), then read the values
    /// back. Both commands are optional in the DDC/CI standard and some
    /// monitors ignore them, so say so if nothing changed.
    func restoreFactoryPicture(for id: CGDirectDisplayID, everything: Bool = false) {
        guard let identity = identities[id] else { return }
        problems[id] = nil
        // Our software dimming sits on top of the hardware: clear it too.
        dimmer.setLevel(1, for: id)
        let before = ddcValues[id] ?? [:]
        let command = everything ? VCP.restoreFactoryDefaults : VCP.restoreFactoryLuminanceContrast
        let ddc = self.ddc
        ddcQueue.async {
            let sent = ddc.write(command, value: 1, for: identity)
            // Give the monitor time to apply it before reading back.
            Thread.sleep(forTimeInterval: 1.5)
            var after: [UInt8: VCPValue] = [:]
            for vcp in [VCP.brightness, VCP.contrast, VCP.volume] {
                if let value = ddc.read(vcp, for: identity) { after[vcp] = value }
            }
            let result = after
            Task { @MainActor [weak self] in
                guard let self else { return }
                let changed = result.contains { vcp, value in before[vcp]?.current != value.current }
                Log.ddc.info("Factory restore (0x\(String(format: "%02X", command), privacy: .public)) on \(identity.name, privacy: .public): sent \(sent), changed \(changed)")
                if !sent {
                    self.problems[id] = "Couldn't send the factory reset"
                } else if !changed && !before.isEmpty {
                    self.problems[id] = everything
                        ? "The monitor ignored the factory reset"
                        : "Monitor ignored it. Try Restore All Factory Settings"
                }
                if !result.isEmpty { self.ddcValues[id] = result }
                self.refresh()
            }
        }
    }

    // MARK: Combined brightness

    private func combinedLevel(of id: CGDirectDisplayID, hardware: VCPValue?) -> Double {
        let software = dimmer.level(for: id)
        if let hardware {
            return BrightnessCurve.combined(
                hardware: Double(hardware.current) / Double(hardware.max),
                software: software
            )
        }
        return BrightnessCurve.dimming(forSoftwareLevel: software)
    }

    /// Set a screen's combined brightness (slider, All Screens or a key).
    func setBrightness(_ level: Double, for id: CGDirectDisplayID) {
        guard let display = displays.first(where: { $0.id == id }),
              display.combinedBrightness != nil else { return }
        let level = min(max(level, 0), 1)
        if let brightness = display.brightness {
            let (hardware, software) = BrightnessCurve.split(level)
            let value = UInt16((hardware * Double(brightness.max)).rounded())
            if value != brightness.current { setVCP(VCP.brightness, to: value, for: id) }
            dimmer.setLevel(software, for: id)
        } else {
            dimmer.setLevel(BrightnessCurve.softwareLevel(forDimming: level), for: id)
        }
        updateRow(id) { $0.combinedBrightness = level }
        if brightnessFollowsAppearance, let key = identities[id]?.key {
            Preferences.setBrightness(level, for: key, dark: isDarkMode)
        }
    }

    // MARK: Light and Dark mode

    private var isDarkMode: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func setBrightnessFollowsAppearance(_ enabled: Bool) {
        Preferences.brightnessFollowsAppearance = enabled
        brightnessFollowsAppearance = enabled
        guard enabled else { return }
        // Start from the current levels for the current mode.
        let dark = isDarkMode
        for display in displays where isAdjustable(display) {
            if let key = identities[display.id]?.key, let level = display.combinedBrightness {
                Preferences.setBrightness(level, for: key, dark: dark)
            }
        }
    }

    /// Bring screens to the brightness last used in the current mode. A
    /// screen with nothing saved for this mode keeps its brightness until you
    /// adjust it, which saves it.
    private func applyAppearanceBrightness(to only: CGDirectDisplayID? = nil) {
        guard brightnessFollowsAppearance else { return }
        let dark = isDarkMode
        for display in displays where isAdjustable(display) && (only == nil || display.id == only) {
            guard let key = identities[display.id]?.key,
                  let level = Preferences.brightness(for: key, dark: dark),
                  abs(level - (display.combinedBrightness ?? level)) > 0.001 else { continue }
            setBrightness(level, for: display.id)
        }
    }

    private func isAdjustable(_ display: ManagedDisplay) -> Bool {
        display.isOn && !display.isBuiltIn && display.combinedBrightness != nil
    }

    /// The All Screens slider: the average combined brightness, shown when
    /// two or more screens can be adjusted.
    var allScreensBrightness: Double? {
        let levels = displays.filter { isAdjustable($0) }.compactMap(\.combinedBrightness)
        guard levels.count > 1 else { return nil }
        return levels.reduce(0, +) / Double(levels.count)
    }

    func setAllScreensBrightness(_ level: Double) {
        for display in displays where isAdjustable(display) {
            setBrightness(level, for: display.id)
        }
    }

    // MARK: Resolution

    /// The slider moved: show the size it points at. Nothing changes on the
    /// screen until the slider is released.
    func previewResolution(_ index: Int, for id: CGDirectDisplayID) {
        resolutionPreview[id] = index
        updateRow(id) { $0.resolutionIndex = index }
    }

    func applyResolution(for id: CGDirectDisplayID) {
        guard let index = resolutionPreview.removeValue(forKey: id),
              let modes = displayModes[id], modes.indices.contains(index) else { return }
        if !DisplayModes.apply(modes[index], to: id) {
            problems[id] = "Couldn't change resolution"
        }
        rebuild(heavy: false)
        scheduleRefresh()
    }

    // MARK: Keyboard keys

    func setBrightnessKeysEnabled(_ enabled: Bool) {
        Preferences.brightnessKeysEnabled = enabled
        brightnessKeysEnabled = enabled
        if enabled && !MediaKeys.hasPermission {
            MediaKeys.requestPermission()
        }
        syncBrightnessKeys()
    }

    /// Start or stop the key tap to match the setting. Until Accessibility is
    /// granted the tap can't start: ask once per launch, then keep retrying
    /// quietly every couple of seconds so the keys work as soon as it's granted.
    private func syncBrightnessKeys() {
        if brightnessKeysEnabled {
            // Event tap: volume keys, and brightness keys from keyboards that
            // send them as events. Needs Accessibility.
            if !keys.isRunning {
                if !MediaKeys.hasPermission && !didPromptForAccessibility {
                    didPromptForAccessibility = true
                    MediaKeys.requestPermission()
                }
                keys.start()
            }
            // Keyboard reader: Apple keyboards' brightness keys. Needs Input Monitoring.
            if !keyboard.isRunning {
                if !KeyboardReader.hasPermission && !didPromptForInputMonitoring {
                    didPromptForInputMonitoring = true
                    KeyboardReader.requestPermission()
                }
                keyboard.start()
            }
        } else {
            keys.stop()
            keyboard.stop()
            stopRepeat()
        }

        let needsAccessibility = brightnessKeysEnabled && !keys.isRunning
        let needsInputMonitoring = brightnessKeysEnabled && !keyboard.isRunning
        if brightnessKeysNeedPermission != needsAccessibility { brightnessKeysNeedPermission = needsAccessibility }
        if inputMonitoringNeeded != needsInputMonitoring { inputMonitoringNeeded = needsInputMonitoring }

        if !keys.isRunning && !keyboard.isRunning {
            keysStatus = nil
        } else if keysStatus == nil {
            keysStatus = "Listening · press a brightness key"
        }

        let waiting = needsAccessibility || needsInputMonitoring
        if waiting, permissionTimer == nil {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncBrightnessKeys() }
            }
        } else if !waiting {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    /// A brightness key from the keyboard reader: step on press, keep
    /// stepping while held (like macOS), stop on release.
    private func keyboardKey(_ key: MediaKey, isDown: Bool) {
        guard isDown else {
            if heldKey == key { stopRepeat() }
            return
        }
        let id = Self.displayUnderPointer() ?? CGMainDisplayID()
        guard canHandle(key, on: id) else { return }
        handle(key, fine: NSEvent.modifierFlags.contains([.shift, .option]), on: id)
        stopRepeat()
        heldKey = key
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startRepeating(key) }
        }
    }

    private func startRepeating(_ key: MediaKey) {
        guard heldKey == key else { return }
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.heldKey == key else { return }
                let id = Self.displayUnderPointer() ?? CGMainDisplayID()
                self.lastStep[key] = nil // repeats are deliberate, never duplicates
                self.handle(key, fine: NSEvent.modifierFlags.contains([.shift, .option]), on: id)
            }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        heldKey = nil
    }

    private static func displayUnderPointer() -> CGDirectDisplayID? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var displayID: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &displayID, &count) == .success, count > 0 else { return nil }
        return displayID
    }

    private func canHandle(_ key: MediaKey, on id: CGDirectDisplayID) -> Bool {
        if key.isBrightness {
            if brightnessTargets(for: id).isEmpty {
                keysStatus = "\(Self.title(of: key)) received, but no screen can be adjusted yet"
                return false
            }
            return true
        }
        return volumeTarget() != nil
    }

    /// Every media-key press the tap sees, for the status line.
    private func keySeen(_ key: MediaKey?, code: Int) {
        guard let key else {
            keysStatus = "Received media key \(code), which Switchboard doesn't use"
            return
        }
        if !key.isBrightness && volumeTarget() == nil {
            keysStatus = "\(Self.title(of: key)) left to macOS (sound isn't on monitor speakers)"
        }
    }

    private static func title(of key: MediaKey) -> String {
        switch key {
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        }
    }

    private func handle(_ key: MediaKey, fine: Bool, on id: CGDirectDisplayID) {
        if key.isBrightness {
            let now = Date()
            if let last = lastStep[key], now.timeIntervalSince(last) < 0.05 { return }
            lastStep[key] = now
        }
        switch key {
        case .brightnessUp, .brightnessDown:
            adjustBrightness(up: key == .brightnessUp, fine: fine, on: id)
        case .volumeUp, .volumeDown, .mute:
            adjustVolume(key, fine: fine)
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

    /// The screens a brightness key aimed at `id` adjusts: that screen and its
    /// mirrors, or, if none of them can be adjusted, every adjustable screen,
    /// so a key press never does nothing.
    private func brightnessTargets(for id: CGDirectDisplayID) -> [ManagedDisplay] {
        let pointed = mirrorSet(of: id).filter { isAdjustable($0) }
        return pointed.isEmpty ? displays.filter { isAdjustable($0) } : pointed
    }

    /// One brightness-key press: step the combined level and bring every
    /// target screen to it, so mirrored screens stay matched.
    private func adjustBrightness(up: Bool, fine: Bool, on id: CGDirectDisplayID) {
        let targets = brightnessTargets(for: id)
        guard let first = targets.first, let current = first.combinedBrightness else { return }
        let level = BrightnessCurve.step(current, up: up, fine: fine)
        for display in targets {
            setBrightness(level, for: display.id)
        }
        hud.show(symbol: level < 0.01 ? "sun.min" : "sun.max.fill", level: level, on: first.id)
        let names = targets.map(\.name).joined(separator: " + ")
        keysStatus = "\(Self.title(of: up ? .brightnessUp : .brightnessDown)) → \(names) · \(Int((level * 100).rounded()))%"
    }

    /// The monitor whose speakers are the current sound output, when macOS
    /// can't set their volume itself.
    private func volumeTarget() -> ManagedDisplay? {
        guard let output = AudioOutput.monitorOutputWithoutVolume() else { return nil }
        let candidates = displays.filter { $0.isOn && $0.volume != nil }
        let named = candidates.first {
            !output.isEmpty && (output.localizedCaseInsensitiveContains($0.name)
                || $0.name.localizedCaseInsensitiveContains(output))
        }
        return named ?? candidates.first
    }

    private func adjustVolume(_ key: MediaKey, fine: Bool) {
        guard let display = volumeTarget(), let volume = display.volume else { return }
        let id = display.id
        let level: Double
        if key == .mute {
            if let restore = mutedVolume.removeValue(forKey: id) {
                level = Double(restore) / Double(volume.max)
            } else {
                mutedVolume[id] = volume.current
                level = 0
            }
        } else {
            mutedVolume[id] = nil
            let current = Double(volume.current) / Double(volume.max)
            level = BrightnessCurve.step(current, up: key == .volumeUp, fine: fine)
        }
        setVCP(VCP.volume, to: UInt16((level * Double(volume.max)).rounded()), for: id)
        let symbol = level < 0.01 ? "speaker.slash.fill"
            : level < 0.34 ? "speaker.wave.1.fill"
            : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        hud.show(symbol: symbol, level: level, on: id)
        keysStatus = "\(Self.title(of: key)) → \(display.name) · \(Int((level * 100).rounded()))%"
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
        // Light/Dark mode changed (by hand or on the Auto schedule). The app's
        // appearance updates a moment after the notification, so wait briefly.
        distributed.addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.applyAppearanceBrightness()
            }
        }
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

    // MARK: Menu state

    /// The screen whose controls are shown: the one picked, else the first
    /// external screen that's on, else the first screen.
    var selectedDisplay: ManagedDisplay? {
        if let id = selectedDisplayID, let display = displays.first(where: { $0.id == id }) {
            return display
        }
        return displays.first { $0.isOn && !$0.isBuiltIn } ?? displays.first
    }

    func select(_ id: CGDirectDisplayID) {
        selectedDisplayID = id
    }

    func toggleSettings() {
        settingsExpanded.toggle()
    }

    /// "Switchboard 1.0" from the bundle (just "Switchboard" under `swift run`).
    var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Version \($0)" } ?? "Development build"
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
        resolutionPreview = [:]
        mutedVolume = [:]
        brightnessFollowsAppearance = Preferences.brightnessFollowsAppearance
        brightnessKeysEnabled = Preferences.brightnessKeysEnabled
        if LoginItem.isAvailable { LoginItem.setEnabled(true) }
        refresh()
    }

    /// Open Privacy & Security → Device Control and Data Access (called
    /// Accessibility before macOS 27). Tries the current Settings URL first,
    /// then the older one.
    func openInputMonitoringSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
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
