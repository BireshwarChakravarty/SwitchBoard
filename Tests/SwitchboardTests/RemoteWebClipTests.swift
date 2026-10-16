import XCTest
@testable import Switchboard

/// The Home Screen icon: embedded in the page, and as a web clip profile.
final class RemoteWebClipTests: XCTestCase {
    private let icon = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])

    func testProfileIsAWebClipWithTheIcon() throws {
        let data = RemoteWebClip.profile(url: "http://mac-mini.local:8723/", icon: icon)
        let profile = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(profile["PayloadType"] as? String, "Configuration")

        let clip = try XCTUnwrap((profile["PayloadContent"] as? [[String: Any]])?.first)
        XCTAssertEqual(clip["PayloadType"] as? String, "com.apple.webClip.managed")
        XCTAssertEqual(clip["URL"] as? String, "http://mac-mini.local:8723/")
        XCTAssertEqual(clip["Label"] as? String, "Switchboard")
        XCTAssertEqual(clip["Icon"] as? Data, icon)
        XCTAssertEqual(clip["FullScreen"] as? Bool, true)
    }

    func testURLComesFromAPlainHostOnly() {
        XCTAssertEqual(RemoteWebClip.url(forHost: "birs-mac-mini.local:8723"), "http://birs-mac-mini.local:8723/")
        XCTAssertEqual(RemoteWebClip.url(forHost: "192.168.1.20:8723"), "http://192.168.1.20:8723/")
        XCTAssertNil(RemoteWebClip.url(forHost: nil))
        XCTAssertNil(RemoteWebClip.url(forHost: ""))
        XCTAssertNil(RemoteWebClip.url(forHost: "evil.example/<script>"))
    }

    func testPageEmbedsTheIcon() {
        let page = RemotePage.page(touchIcon: icon)
        XCTAssertTrue(page.contains(#"<link rel="apple-touch-icon" sizes="180x180" href="data:image/png;base64,\#(icon.base64EncodedString())">"#))
        XCTAssertFalse(page.contains(RemotePage.touchIconPlaceholder))
    }

    func testPageLinksTheIconWhenThereIsNone() {
        let page = RemotePage.page(touchIcon: nil)
        XCTAssertTrue(page.contains(#"<link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png?v=3">"#))
        XCTAssertFalse(page.contains(RemotePage.touchIconPlaceholder))
    }
}
