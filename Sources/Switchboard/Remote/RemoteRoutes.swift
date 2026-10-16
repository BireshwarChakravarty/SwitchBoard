import Foundation

/// What a remote request asks for. Decoding is kept separate from acting on
/// it so it can be unit-tested without displays.
///
///     GET  /                                     the web remote
///     GET  /Switchboard.mobileconfig             Home Screen web clip profile
///     GET  /api/screens                          every screen's state
///     POST /api/pair                             {"code": "123456"} → {"key": …}
///     POST /api/screens/<screen>/on|off|toggle   power
///     POST /api/screens/<screen>/<control>/<n>   brightness, contrast or volume
///                                                0–100, or resolution (an index)
///     POST /api/screens/all/brightness/<n>       every screen's brightness
///
/// `<screen>` is a screen's name (any case, spaces optional), the start of
/// it, or its display ID.
enum RemoteRoute: Equatable {
    case page
    case manifest
    case icon
    case webClip
    case state
    case pair
    case power(screen: String, on: Bool?) // nil: toggle
    case set(screen: String, control: RemoteControlKind, value: Int)

    /// Whether the route needs a paired key.
    var needsKey: Bool {
        switch self {
        case .page, .manifest, .icon, .webClip, .pair: false
        default: true
        }
    }

    enum Failure: Error, Equatable {
        case notFound
        case methodNotAllowed
        case badValue(String)
    }

    static func resolve(method: String, path: [String]) -> Result<RemoteRoute, Failure> {
        let isGet = method == "GET" || method == "HEAD"
        let isPost = method == "POST"
        func get(_ route: RemoteRoute) -> Result<RemoteRoute, Failure> {
            isGet ? .success(route) : .failure(.methodNotAllowed)
        }
        func post(_ route: RemoteRoute) -> Result<RemoteRoute, Failure> {
            isPost ? .success(route) : .failure(.methodNotAllowed)
        }

        switch path {
        case []:
            return get(.page)
        case ["manifest.webmanifest"]:
            return get(.manifest)
        case ["icon.png"], ["apple-touch-icon.png"], ["apple-touch-icon-precomposed.png"]:
            return get(.icon)
        case [RemoteWebClip.fileName]:
            return get(.webClip)
        case ["api", "screens"]:
            return get(.state)
        case ["api", "pair"]:
            return post(.pair)
        case let p where p.count == 4 && p[0] == "api" && p[1] == "screens":
            let on: Bool?
            switch p[3].lowercased() {
            case "on": on = true
            case "off": on = false
            case "toggle": on = nil
            default: return .failure(.notFound)
            }
            return post(.power(screen: p[2], on: on))
        case let p where p.count == 5 && p[0] == "api" && p[1] == "screens":
            guard let control = RemoteControlKind(rawValue: p[3].lowercased()) else { return .failure(.notFound) }
            // Siri and Shortcuts may send "40.5" or "40%": round to a whole number.
            let text = p[4].replacingOccurrences(of: "%", with: "")
            guard let number = Double(text), number.isFinite else {
                return .failure(.badValue("\(p[4]) isn't a number"))
            }
            let value = Int(number.rounded())
            if control == .resolution {
                guard value >= 0 else { return .failure(.badValue("Resolution must be 0 or more")) }
            } else {
                guard (0...100).contains(value) else { return .failure(.badValue("Use a value from 0 to 100")) }
            }
            return post(.set(screen: p[2], control: control, value: value))
        default:
            return .failure(.notFound)
        }
    }
}

enum RemoteControlKind: String, Equatable, CaseIterable {
    case brightness, contrast, volume, resolution
}

enum RemoteScreenMatcher {
    /// Lower case, letters and digits only: "XV272K V5" → "xv272kv5".
    static func normalize(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// The URL-friendly name used in shortcut links: "XV272K V5" → "xv272k-v5".
    static func slug(_ name: String) -> String {
        let words = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return words.isEmpty ? "screen" : words.joined(separator: "-")
    }

    /// The screen a name or ID refers to: an exact ID, an exact name, then a
    /// name that starts with or contains it. Nil if none, or if ambiguous.
    static func match(_ query: String, in screens: [(id: UInt32, name: String)]) -> UInt32? {
        if let id = UInt32(query), screens.contains(where: { $0.id == id }) { return id }
        let wanted = normalize(query)
        guard !wanted.isEmpty else { return nil }
        let names = screens.map { ($0.id, normalize($0.name)) }
        for test in [{ (name: String) in name == wanted },
                     { (name: String) in name.hasPrefix(wanted) },
                     { (name: String) in name.contains(wanted) }] {
            let hits = names.filter { test($0.1) }
            if hits.count == 1 { return hits[0].0 }
            if hits.count > 1 { return nil }
        }
        return nil
    }
}
