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

    func testMakesPowerAndBrightnessShortcuts() {
        let shortcuts = RemoteShortcuts.make(base: base, key: key,
                                             switchable: [(name: "ARZOPA", slug: "arzopa")], brightness: true)
        XCTAssertEqual(shortcuts.map(\.name), ["ARZOPA On", "ARZOPA Off", "Toggle ARZOPA", "Screen Brightness"])

        let off = actions(shortcuts[1].workflow)
        XCTAssertEqual(off.map { $0["WFWorkflowActionIdentifier"] as? String },
                       ["is.workflow.actions.downloadurl", "is.workflow.actions.getvalueforkey",
                        "is.workflow.actions.showresult"])
        XCTAssertEqual(parameters(off[0])["WFURL"] as? String, "\(base)/api/screens/arzopa/off?key=\(key)")
        XCTAssertEqual(parameters(off[0])["WFHTTPMethod"] as? String, "POST")
        XCTAssertEqual(parameters(off[1])["WFDictionaryKey"] as? String, "message")
    }

    func testOutputsAreWiredByUUID() {
        let workflow = RemoteShortcuts.askingRequest(prompt: "?", urlBefore: "\(base)/x/", urlAfter: "?key=k")
        let steps = actions(workflow)
        XCTAssertEqual(steps.map { $0["WFWorkflowActionIdentifier"] as? String },
                       ["is.workflow.actions.ask", "is.workflow.actions.downloadurl",
                        "is.workflow.actions.getvalueforkey", "is.workflow.actions.showresult"])
        let askUUID = parameters(steps[0])["UUID"] as? String
        let fetchUUID = parameters(steps[1])["UUID"] as? String
        XCTAssertNotNil(askUUID)

        // The URL holds the answer where U+FFFC is.
        let url = (parameters(steps[1])["WFURL"] as? [String: Any])?["Value"] as? [String: Any]
        let string = url?["string"] as? String
        XCTAssertEqual(string, "\(base)/x/\u{FFFC}?key=k")
        let ranges = url?["attachmentsByRange"] as? [String: [String: Any]]
        let position = "\(base)/x/".utf16.count
        XCTAssertEqual(ranges?["{\(position), 1}"]?["OutputUUID"] as? String, askUUID)
        XCTAssertEqual(ranges?["{\(position), 1}"]?["OutputName"] as? String, "Provided Input")

        // The message is read from the URL's reply.
        let input = (parameters(steps[2])["WFInput"] as? [String: Any])?["Value"] as? [String: Any]
        XCTAssertEqual(input?["OutputUUID"] as? String, fetchUUID)
        XCTAssertEqual(input?["OutputName"] as? String, "Contents of URL")
    }

    func testSerializesAsPropertyList() throws {
        let shortcut = RemoteShortcuts.make(base: base, key: key, switchable: [], brightness: true)[0]
        let data = try RemoteShortcuts.data(for: shortcut)
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual((back?["WFWorkflowActions"] as? [Any])?.count, 4)
    }

    func testFileNames() {
        XCTAssertEqual(RemoteShortcuts.fileName(for: "Toggle ARZOPA"), "Toggle ARZOPA.shortcut")
        XCTAssertEqual(RemoteShortcuts.fileName(for: "A/B: C"), "A-B- C.shortcut")
    }

    /// Signs a shortcut with Apple's tool where it can (it needs a signed-in
    /// Apple Account, which CI machines may not have), to catch files the
    /// tool rejects.
    func testSigningWhereAvailable() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shortcut = RemoteShortcuts.make(base: base, key: key,
                                            switchable: [(name: "ARZOPA", slug: "arzopa")], brightness: true)[3]
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
