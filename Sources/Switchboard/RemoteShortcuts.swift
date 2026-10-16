import Foundation

/// Builds ready-made Shortcuts for the iPhone Remote: "ARZOPA On",
/// "ARZOPA Off", "Toggle ARZOPA" for each screen with a power switch, and
/// "Screen Brightness", which asks for a number.
///
/// Each one calls the remote's API with Get Contents of URL (POST) and shows
/// the reply's `message`, which Siri reads out. macOS and iOS only import
/// signed shortcut files, so the files are signed on this Mac with Apple's
/// `shortcuts sign` tool, then opened in the Shortcuts app; iCloud brings
/// them to the iPhone.
enum RemoteShortcuts {
    struct Shortcut {
        /// Also the file name, which becomes the shortcut's name on import.
        let name: String
        let workflow: [String: Any]
    }

    /// The shortcuts for these screens. `base` is like
    /// "http://Mac-mini.local:8723".
    static func make(base: String, key: String, switchable: [(name: String, slug: String)],
                     brightness: Bool) -> [Shortcut] {
        var shortcuts: [Shortcut] = []
        for screen in switchable {
            for (title, action) in [("\(screen.name) On", "on"),
                                    ("\(screen.name) Off", "off"),
                                    ("Toggle \(screen.name)", "toggle")] {
                let url = "\(base)/api/screens/\(screen.slug)/\(action)?key=\(key)"
                shortcuts.append(Shortcut(name: title, workflow: request(url: url)))
            }
        }
        if brightness {
            shortcuts.append(Shortcut(
                name: "Screen Brightness",
                workflow: askingRequest(
                    prompt: "What brightness, from 0 to 100?",
                    urlBefore: "\(base)/api/screens/all/brightness/",
                    urlAfter: "?key=\(key)"
                )
            ))
        }
        return shortcuts
    }

    /// A file name for a shortcut name ("/" and ":" aren't allowed).
    static func fileName(for name: String) -> String {
        let cleaned = name.map { "/:\\".contains($0) ? "-" : $0 }
        return String(cleaned) + ".shortcut"
    }

    /// The unsigned shortcut file (a binary property list).
    static func data(for shortcut: Shortcut) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: shortcut.workflow, format: .binary, options: 0)
    }

    // MARK: Workflows

    /// POST to `url`, then show the reply's message.
    static func request(url: String) -> [String: Any] {
        let fetch = UUID().uuidString
        return workflow(actions: [fetchAction(uuid: fetch, url: url)] + showMessage(from: fetch))
    }

    /// Ask for a number, POST to `urlBefore` + number + `urlAfter`, then show
    /// the reply's message.
    static func askingRequest(prompt: String, urlBefore: String, urlAfter: String) -> [String: Any] {
        let ask = UUID().uuidString
        let fetch = UUID().uuidString
        let askAction: [String: Any] = [
            "WFWorkflowActionIdentifier": "is.workflow.actions.ask",
            "WFWorkflowActionParameters": [
                "UUID": ask,
                "WFAskActionPrompt": prompt,
                "WFInputType": "Number",
                "WFAllowsDecimalNumbers": false
            ] as [String: Any]
        ]
        let url = tokenString(before: urlBefore, output: (ask, "Provided Input"), after: urlAfter)
        return workflow(actions: [askAction, fetchAction(uuid: fetch, url: url)] + showMessage(from: fetch))
    }

    private static func fetchAction(uuid: String, url: Any) -> [String: Any] {
        [
            "WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl",
            "WFWorkflowActionParameters": [
                "UUID": uuid,
                "WFURL": url,
                "WFHTTPMethod": "POST"
            ] as [String: Any]
        ]
    }

    /// Get the "message" from the reply and show it (Siri speaks it).
    private static func showMessage(from fetch: String) -> [[String: Any]] {
        let value = UUID().uuidString
        return [
            [
                "WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey",
                "WFWorkflowActionParameters": [
                    "UUID": value,
                    "WFDictionaryKey": "message",
                    "WFInput": [
                        "Value": output(fetch, "Contents of URL"),
                        "WFSerializationType": "WFTextTokenAttachment"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "WFWorkflowActionIdentifier": "is.workflow.actions.showresult",
                "WFWorkflowActionParameters": [
                    "Text": tokenString(before: "", output: (value, "Dictionary Value"), after: "")
                ] as [String: Any]
            ]
        ]
    }

    private static func output(_ uuid: String, _ name: String) -> [String: Any] {
        ["OutputUUID": uuid, "Type": "ActionOutput", "OutputName": name]
    }

    /// Text with one action's output inserted between `before` and `after`.
    /// The output sits at U+FFFC; its range counts UTF-16 code units.
    static func tokenString(before: String, output source: (uuid: String, name: String), after: String) -> [String: Any] {
        let position = before.utf16.count
        return [
            "Value": [
                "string": before + "\u{FFFC}" + after,
                "attachmentsByRange": ["{\(position), 1}": output(source.uuid, source.name)]
            ] as [String: Any],
            "WFSerializationType": "WFTextTokenString"
        ]
    }

    private static func workflow(actions: [[String: Any]]) -> [String: Any] {
        [
            "WFWorkflowClientVersion": "2607.0.4",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": [
                "WFWorkflowIconStartColor": 4_282_601_983,
                "WFWorkflowIconGlyphNumber": 59_511
            ] as [String: Any],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowInputContentItemClasses": [Any](),
            "WFWorkflowOutputContentItemClasses": [Any](),
            "WFWorkflowTypes": [Any](),
            "WFQuickActionSurfaces": [Any](),
            "WFWorkflowHasShortcutInputVariables": false,
            "WFWorkflowActions": actions
        ]
    }
}

/// Signs shortcut files with Apple's `shortcuts sign` (macOS 12 and later).
enum ShortcutSigner {
    static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    struct Failure: Error {
        let message: String
    }

    /// Sign `input` into `output`. Tries "anyone" (works on any device),
    /// then "people-who-know-me" (your own devices), which needs no
    /// round trip to Apple.
    static func sign(_ input: URL, to output: URL) -> Result<Void, Failure> {
        var lastError = "The shortcuts tool isn't available"
        guard FileManager.default.isExecutableFile(atPath: tool.path) else { return .failure(Failure(message: lastError)) }
        for mode in ["anyone", "people-who-know-me"] {
            try? FileManager.default.removeItem(at: output)
            let process = Process()
            process.executableURL = tool
            process.arguments = ["sign", "--mode", mode, "--input", input.path, "--output", output.path]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = Pipe()
            do {
                try process.run()
            } catch {
                lastError = error.localizedDescription
                continue
            }
            process.waitUntilExit()
            let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) {
                return .success(())
            }
            lastError = text.isEmpty ? "shortcuts sign failed (\(process.terminationStatus))" : text
        }
        return .failure(Failure(message: lastError))
    }
}
