import Foundation
import AppKit
import SystemConfiguration

/// The iPhone remote: a web page and a small HTTP API on the local network,
/// used by the page and by Shortcuts. Off unless turned on in Settings.
///
/// It acts only through DisplayController's public controls, the same ones
/// the menu uses, so the remote can't do anything the menu can't, and it
/// respects the same rules (a hidden power switch can't be used remotely;
/// the last screen that's on can't be switched off).
@MainActor
final class RemoteControl: ObservableObject {
    static let port: UInt16 = 8723

    @Published private(set) var isEnabled = Preferences.remoteEnabled
    @Published private(set) var isListening = false
    @Published private(set) var problem: String?
    @Published private(set) var code = ""
    @Published private(set) var pairedCount = 0
    /// Progress or result of Add Shortcuts to Siri.
    @Published private(set) var shortcutsStatus: String?
    @Published private(set) var isMakingShortcuts = false

    private weak var controller: DisplayController?
    private var server: RemoteServer?
    private var pairing = RemotePairing(keyHashes: Preferences.remoteKeyHashes)
    private var iconData: Data?

    /// Connect to the controller and start if the remote was left on.
    func attach(to controller: DisplayController) {
        self.controller = controller
        code = pairing.code
        pairedCount = pairing.keyHashes.count
        if isEnabled { start() }
    }

    func setEnabled(_ enabled: Bool) {
        Preferences.remoteEnabled = enabled
        isEnabled = enabled
        if enabled {
            pairing.renewCode()
            code = pairing.code
            start()
        } else {
            stop()
        }
    }

    func newCode() {
        pairing.renewCode()
        code = pairing.code
    }

    func forgetPairedDevices() {
        pairing.forgetAllKeys()
        savePairing()
    }

    /// Reset to Defaults: turn the remote off and forget paired devices.
    func reset() {
        stop()
        Preferences.remoteEnabled = false
        isEnabled = false
        pairing.forgetAllKeys()
        savePairing()
        newCode()
    }

    /// "http://Bireshwars-Mac-mini.local:8723", for typing into Safari.
    var address: String {
        let host = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
            ?? Self.localIPv4Address()
            ?? "this Mac's address"
        return "http://\(host):\(Self.port)"
    }

    /// The Mac's IPv4 address on the local network, in case `.local` names
    /// don't resolve on the phone's network.
    var fallbackAddress: String? {
        Self.localIPv4Address().map { "http://\($0):\(Self.port)" }
    }

    // MARK: Shortcuts

    /// Build, sign and open a "Toggle <screen>" shortcut for Siri. It gets
    /// its own key (counted as a paired device).
    func addShortcut(for id: CGDirectDisplayID) {
        guard let controller, !isMakingShortcuts,
              let display = controller.displays.first(where: { $0.id == id }) else { return }
        let key = pairing.issueKey()
        let shortcut = RemoteShortcuts.toggle(
            base: address, key: key,
            screen: (name: display.name, slug: RemoteScreenMatcher.slug(display.name))
        )
        guard let data = try? RemoteShortcuts.data(for: shortcut) else {
            pairing.revoke(key: key)
            shortcutsStatus = "Couldn't make the shortcut"
            return
        }
        savePairing()
        isMakingShortcuts = true
        let name = shortcut.name
        shortcutsStatus = "Making “\(name)”…"

        let files = [(name: RemoteShortcuts.fileName(for: name), data: data)]
        Task.detached {
            let result = Self.writeAndSign(files)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isMakingShortcuts = false
                switch result {
                case .success(let urls):
                    Log.app.info("Remote: made shortcut \(name, privacy: .public)")
                    self.open(urls)
                    self.shortcutsStatus = "Opened “\(name)” in Shortcuts. Click Add Shortcut; iCloud brings it to your iPhone."
                case .failure(let failure):
                    Log.app.error("Remote: shortcut failed: \(failure.message, privacy: .public)")
                    self.pairing.revoke(key: key)
                    self.savePairing()
                    self.shortcutsStatus = "Couldn't make the shortcut: \(failure.message)"
                }
            }
        }
    }

    /// Write each shortcut, sign it into ~/Downloads/Switchboard Shortcuts
    /// (replacing older files there, which hold an older key), and return
    /// the signed files.
    nonisolated private static func writeAndSign(_ files: [(name: String, data: Data)]) -> Result<[URL], ShortcutSigner.Failure> {
        let manager = FileManager.default
        let downloads = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let folder = downloads.appendingPathComponent("Switchboard Shortcuts", isDirectory: true)
        let scratch = manager.temporaryDirectory.appendingPathComponent("switchboard-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: scratch) }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
            for old in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where old.pathExtension == "shortcut" {
                try? manager.removeItem(at: old)
            }
        } catch {
            return .failure(ShortcutSigner.Failure(message: error.localizedDescription))
        }

        var signed: [URL] = []
        for file in files {
            let unsigned = scratch.appendingPathComponent(file.name)
            let output = folder.appendingPathComponent(file.name)
            do {
                try file.data.write(to: unsigned)
            } catch {
                return .failure(ShortcutSigner.Failure(message: error.localizedDescription))
            }
            if case .failure(let failure) = ShortcutSigner.sign(unsigned, to: output) {
                return .failure(failure)
            }
            signed.append(output)
        }
        return .success(signed)
    }

    /// Open the signed files in the Shortcuts app, which offers to add each.
    private func open(_ urls: [URL]) {
        let configuration = NSWorkspace.OpenConfiguration()
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
        } else {
            urls.forEach { NSWorkspace.shared.open($0) }
        }
    }

    // MARK: Server

    private func start() {
        guard server == nil else { return }
        problem = nil
        let server = RemoteServer { [weak self] request in
            guard let self else { return .error("Switchboard is quitting", status: 503) }
            return await self.handle(request)
        }
        self.server = server
        server.start(port: Self.port) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch result {
                case .success:
                    self.isListening = true
                    self.problem = nil
                case .failure:
                    self.isListening = false
                    self.server = nil
                    self.problem = "Port \(Self.port) is in use by another app"
                }
            }
        }
    }

    private func stop() {
        server?.stop()
        server = nil
        isListening = false
    }

    private func savePairing() {
        Preferences.remoteKeyHashes = pairing.keyHashes
        pairedCount = pairing.keyHashes.count
    }

    // MARK: Requests

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let route: RemoteRoute
        switch RemoteRoute.resolve(method: request.method, path: request.pathComponents) {
        case .success(let resolved): route = resolved
        case .failure(.notFound): return .error("Not found", status: 404)
        case .failure(.methodNotAllowed): return .error("Use POST for actions and GET to read", status: 405)
        case .failure(.badValue(let message)): return .error(message, status: 400)
        }

        if route.needsKey && !pairing.accepts(key: RemotePairing.key(in: request)) {
            return .error("This device isn't paired. Open the remote and enter the code shown on the Mac.", status: 401)
        }
        guard let controller else { return .error("Switchboard isn't ready", status: 503) }

        switch route {
        case .page:
            return HTTPResponse(status: 200, contentType: "text/html; charset=utf-8",
                                body: Data(RemotePage.page(touchIcon: icon()).utf8))
        case .manifest:
            return HTTPResponse(status: 200, contentType: "application/manifest+json", body: Data(RemotePage.manifest.utf8))
        case .icon:
            // Cacheable, so Safari can keep it for the Home Screen.
            return HTTPResponse(status: 200, contentType: "image/png", body: icon(),
                                cacheControl: "public, max-age=86400")
        case .webClip:
            let url = RemoteWebClip.url(forHost: request.headers["host"]) ?? "\(address)/"
            return HTTPResponse(status: 200, contentType: RemoteWebClip.contentType,
                                body: RemoteWebClip.profile(url: url, icon: icon()),
                                extraHeaders: ["Content-Disposition": "attachment; filename=\"\(RemoteWebClip.fileName)\""])
        case .state:
            return .json(state(of: controller))
        case .pair:
            return pair(request)
        case .power(let screen, let on):
            return power(screen, on: on, controller: controller)
        case .set(let screen, let control, let value):
            return set(control, of: screen, to: value, controller: controller)
        }
    }

    private func pair(_ request: HTTPRequest) -> HTTPResponse {
        struct Body: Decodable { let code: String }
        guard let body = try? JSONDecoder().decode(Body.self, from: request.body) else {
            return .error("Send {\"code\": \"123456\"}", status: 400)
        }
        let result = pairing.pair(with: body.code)
        code = pairing.code
        switch result {
        case .paired(let key):
            savePairing()
            Log.app.info("Remote: a device paired")
            return .json(["key": key])
        case .wrongCode:
            return .error("That code isn't right. Check Switchboard → Settings on the Mac.", status: 401)
        case .codeReplaced:
            Log.app.notice("Remote: too many wrong codes; code replaced")
            return .error("Too many wrong codes. The Mac now shows a new one.", status: 429)
        }
    }

    private func power(_ query: String, on: Bool?, controller: DisplayController) -> HTTPResponse {
        guard let display = find(query, in: controller) else { return noScreen(query) }
        let target = on ?? !display.isOn
        if target == display.isOn {
            return .json(ActionResult(message: "\(display.name) is already \(target ? "on" : "off")",
                                      power: target ? "On" : "Off", state: state(of: controller)))
        }
        guard display.canToggle else {
            return .error("\(display.name) can't be switched off", status: 409)
        }
        guard !controller.isSwitchHidden(display.id) else {
            return .error("\(display.name)'s power switch is hidden in Switchboard", status: 409)
        }
        guard display.showsSwitch || target else {
            return .error("\(display.name) is the only screen that's on", status: 409)
        }
        controller.setPower(on: target, for: display.id)
        if let problem = controller.displays.first(where: { $0.id == display.id })?.problem {
            return .error(problem, status: 409)
        }
        return .json(ActionResult(message: "\(display.name) switched \(target ? "on" : "off")",
                                  power: target ? "On" : "Off", state: state(of: controller)))
    }

    private func set(_ control: RemoteControlKind, of query: String, to value: Int,
                     controller: DisplayController) -> HTTPResponse {
        if query.lowercased() == "all" {
            guard control == .brightness else {
                return .error("Only brightness can be set for all screens", status: 400)
            }
            controller.setAllScreensBrightness(Double(value) / 100)
            return .json(ActionResult(message: "All screens at \(value)%", state: state(of: controller)))
        }
        guard let display = find(query, in: controller) else { return noScreen(query) }
        guard display.isOn else { return .error("\(display.name) is switched off", status: 409) }

        switch control {
        case .brightness:
            guard display.combinedBrightness != nil else { return unsupported(control, display) }
            controller.setBrightness(Double(value) / 100, for: display.id)
        case .contrast, .volume:
            let vcp = control == .contrast ? VCP.contrast : VCP.volume
            guard let current = control == .contrast ? display.contrast : display.volume else {
                return unsupported(control, display)
            }
            let raw = UInt16((Double(value) / 100 * Double(current.max)).rounded())
            controller.setVCP(vcp, to: raw, for: display.id)
        case .resolution:
            guard display.resolutions.indices.contains(value) else {
                return .error("\(display.name) has resolutions 0 to \(max(display.resolutions.count - 1, 0))", status: 400)
            }
            controller.previewResolution(value, for: display.id)
            controller.applyResolution(for: display.id)
            return .json(ActionResult(message: "\(display.name) at \(display.resolutions[value].label)",
                                      state: state(of: controller)))
        }
        return .json(ActionResult(message: "\(display.name) \(control.rawValue) \(value)%",
                                  state: state(of: controller)))
    }

    private func find(_ query: String, in controller: DisplayController) -> ManagedDisplay? {
        let screens = controller.displays.map { (id: UInt32($0.id), name: $0.name) }
        guard let id = RemoteScreenMatcher.match(query, in: screens) else { return nil }
        return controller.displays.first { $0.id == id }
    }

    private func noScreen(_ query: String) -> HTTPResponse {
        .error("No screen matches \"\(query)\"", status: 404)
    }

    private func unsupported(_ control: RemoteControlKind, _ display: ManagedDisplay) -> HTTPResponse {
        .error("\(display.name) has no \(control.rawValue) control", status: 409)
    }

    // MARK: State

    private struct ActionResult: Encodable {
        let message: String
        /// Power actions only: "On" or "Off", what the screen is now. The
        /// Toggle shortcut says it as "Monitor On" or "Monitor Off".
        var power: String?
        let state: RemoteState

        init(message: String, power: String? = nil, state: RemoteState) {
            self.message = message
            self.power = power
            self.state = state
        }
    }

    struct RemoteState: Encodable {
        let mac: String
        let version: String
        let allScreens: Int?
        let screens: [Screen]

        struct Screen: Encodable {
            let id: UInt32
            let name: String
            let slug: String
            let isOn: Bool
            let isBuiltIn: Bool
            let canSwitch: Bool
            let note: String?
            let problem: String?
            let brightness: Int?
            let contrast: Int?
            let volume: Int?
            let resolutions: [String]
            let resolution: Int?
        }
    }

    private func state(of controller: DisplayController) -> RemoteState {
        func percent(_ value: VCPValue?) -> Int? {
            guard let value, value.max > 0 else { return nil }
            return Int((Double(value.current) / Double(value.max) * 100).rounded())
        }
        let screens = controller.displays.map { display in
            RemoteState.Screen(
                id: UInt32(display.id),
                name: display.name,
                slug: RemoteScreenMatcher.slug(display.name),
                isOn: display.isOn,
                isBuiltIn: display.isBuiltIn,
                canSwitch: display.canToggle && display.showsSwitch && !controller.isSwitchHidden(display.id),
                note: display.mirrorNote,
                problem: display.problem,
                brightness: display.combinedBrightness.map { Int(($0 * 100).rounded()) },
                contrast: percent(display.contrast),
                volume: percent(display.volume),
                resolutions: display.resolutions.map(\.label),
                resolution: display.resolutions.isEmpty ? nil : display.resolutionIndex
            )
        }
        return RemoteState(
            mac: Host.current().localizedName ?? "Mac",
            version: controller.versionLabel,
            allScreens: controller.allScreensBrightness.map { Int(($0 * 100).rounded()) },
            screens: screens
        )
    }

    // MARK: Helpers

    /// The iPhone Home Screen icon: the bundled full-bleed TouchIcon.png
    /// (iOS masks it and would fill a Mac icon's transparent margin with
    /// black). Outside an app bundle (`swift run`), the app icon is drawn
    /// instead.
    private func icon() -> Data {
        if let iconData { return iconData }
        if let url = Bundle.main.url(forResource: "TouchIcon", withExtension: "png"),
           let data = try? Data(contentsOf: url) {
            iconData = data
            return data
        }
        let size = NSSize(width: 180, height: 180)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSApp.applicationIconImage.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:]) ?? Data()
        iconData = data
        return data
    }

    private static func localIPv4Address() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var found: String?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name).hasPrefix("en"),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                found = String(cString: host)
                break
            }
        }
        return found
    }
}
