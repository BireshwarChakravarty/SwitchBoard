import XCTest
@testable import Switchboard

/// Ready-made Shortcuts for Siri.
final class RemoteShortcutsTests: XCTestCase {
    private let base = "http://Mac-mini.local:8723"
    private let key = String(repeating: "a", count: 64)

    private func actions(_ workflow: [String: Any]) -> [[String: Any]] {
        workflow["WFWorkflowActions"] as? [[String: Any]] ?? []
    }

    private func parameters(_ action: [String: Any]) -> [String: Any] {
        action["WFWorkflowActionParameters"] as? [String: Any] ?? [:]
    }

    func testMakesOneToggleMonitorShortcut() {
        let shortcut = RemoteShortcuts.toggle(base: base, key: key, screen: (name: "ARZOPA", slug: "arzopa"))
        XCTAssertEqual(shortcut.name, "Toggle Monitor")

        let steps = actions(shortcut.workflow)
        XCTAssertEqual(steps.map { $0["WFWorkflowActionIdentifier"] as? String },
                       ["is.workflow.actions.downloadurl", "is.workflow.actions.getvalueforkey",
                        "is.workflow.actions.showresult"])
        XCTAssertEqual(parameters(steps[0])["WFURL"] as? String, "\(base)/api/screens/arzopa/toggle?key=\(key)")
        XCTAssertEqual(parameters(steps[0])["WFHTTPMethod"] as? String, "POST")
        XCTAssertEqual(parameters(steps[1])["WFDictionaryKey"] as? String, "power")
    }

    /// Siri says "Monitor On" or "Monitor Off": "Monitor " then the reply's
    /// `power`, read from the URL's reply.
    func testSaysMonitorAndThePowerState() {
        let shortcut = RemoteShortcuts.toggle(base: base, key: key, screen: (name: "ARZOPA", slug: "arzopa"))
        let steps = actions(shortcut.workflow)
        let fetchUUID = parameters(steps[0])["UUID"] as? String
        let valueUUID = parameters(steps[1])["UUID"] as? String
        XCTAssertNotNil(fetchUUID)

        let input = (parameters(steps[1])["WFInput"] as? [String: Any])?["Value"] as? [String: Any]
        XCTAssertEqual(input?["OutputUUID"] as? String, fetchUUID)
        XCTAssertEqual(input?["OutputName"] as? String, "Contents of URL")

        let text = (parameters(steps[2])["Text"] as? [String: Any])?["Value"] as? [String: Any]
        XCTAssertEqual(text?["string"] as? String, "Monitor \u{FFFC}")
        let ranges = text?["attachmentsByRange"] as? [String: [String: Any]]
        XCTAssertEqual(ranges?["{8, 1}"]?["OutputUUID"] as? String, valueUUID)
    }

    func testSerializesAsPropertyList() throws {
        let shortcut = RemoteShortcuts.toggle(base: base, key: key, screen: (name: "ARZOPA", slug: "arzopa"))
        let data = try RemoteShortcuts.data(for: shortcut)
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual((back?["WFWorkflowActions"] as? [Any])?.count, 3)
    }

    func testFileNames() {
        XCTAssertEqual(RemoteShortcuts.fileName(for: "Toggle Monitor"), "Toggle Monitor.shortcut")
        XCTAssertEqual(RemoteShortcuts.fileName(for: "A/B: C"), "A-B- C.shortcut")
    }

    /// Signs a shortcut with Apple's tool where it can (it needs a signed-in
    /// Apple Account, which CI machines may not have), to catch files the
    /// tool rejects.
    func testSigningWhereAvailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shortcut = RemoteShortcuts.toggle(base: base, key: key, screen: (name: "ARZOPA", slug: "arzopa"))
        let input = folder.appendingPathComponent("in.shortcut")
        try RemoteShortcuts.data(for: shortcut).write(to: input)
        let output = folder.appendingPathComponent("out.shortcut")
        switch ShortcutSigner.sign(input, to: output) {
        case .success:
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
            print("Shortcut signing: OK (\(size) bytes)")
            XCTAssertGreaterThan(size, 0)
        case .failure(let failure):
            throw XCTSkip("Shortcut signing unavailable here: \(failure.message)")
        }
    }
}
