import Foundation

/// A configuration profile that adds the remote to an iPhone's Home Screen
/// as a web clip, with Switchboard's icon embedded.
///
/// Safari's Add to Home Screen fetches the page's icon separately, and for a
/// plain-HTTP address on the local network it can fall back to a letter
/// instead. A web clip carries its icon inside the profile, so it always
/// shows. The profile contains only the remote's address and the icon, no
/// keys; the web clip pairs like Safari does.
enum RemoteWebClip {
    static let contentType = "application/x-apple-aspen-config"
    static let fileName = "Switchboard.mobileconfig"

    /// Fixed identifiers, so installing the profile again replaces it.
    private static let profileUUID = "3E1B6C8A-7D24-4F0B-9C51-2A8E6D4B7F10"
    private static let clipUUID = "9A4F2E71-0C3B-4D8E-B6A5-71E0C9D25B34"

    /// The profile for a remote at `url`, such as "http://Mac-mini.local:8723/".
    static func profile(url: String, icon: Data) -> Data {
        let clip: [String: Any] = [
            "PayloadType": "com.apple.webClip.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": "app.switchboard.Switchboard.remote.webclip",
            "PayloadUUID": clipUUID,
            "PayloadDisplayName": "Switchboard",
            "Label": "Switchboard",
            "URL": url,
            "Icon": icon,
            "Precomposed": true,
            "FullScreen": true,
            "IsRemovable": true
        ]
        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": "app.switchboard.Switchboard.remote",
            "PayloadUUID": profileUUID,
            "PayloadDisplayName": "Switchboard Remote",
            "PayloadDescription": "Adds Switchboard to your Home Screen. It opens the remote at \(url).",
            "PayloadOrganization": "Switchboard",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [clip]
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)) ?? Data()
    }

    /// The remote's address as the phone reached it, from the request's Host
    /// header ("Mac-mini.local:8723"). Nil if missing or not a plain host.
    static func url(forHost host: String?) -> String? {
        guard let host, !host.isEmpty,
              host.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || ".-:[]".unicodeScalars.contains($0) })
        else { return nil }
        return "http://\(host)/"
    }
}
