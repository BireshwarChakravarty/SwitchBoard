import Foundation

/// Builds the ready-made Siri shortcut for the iPhone Remote: "Toggle
/// Monitor", which switches one screen on or off and says "Monitor On" or
/// "Monitor Off".
///
/// It calls the remote's API with Get Contents of URL (POST) and shows the
/// reply's `power`, which Siri reads out. macOS and iOS only import signed
/// shortcut files, so the file is signed on this Mac with Apple's
/// `shortcuts sign` tool, then opened in the Shortcuts app; iCloud brings it
/// to the iPhone.
enum RemoteShortcuts {
    struct Shortcut {
        /// Also the file name, which becomes the shortcut's name on import.
        let name: String
        let workflow: [String: Any]
    }

    static let toggleName = "Toggle Monitor"

    /// "Toggle Monitor" for `screen`. `base` is like "http://Mac-mini.local:8723".
    static func toggle(base: String, key: String, screen: (name: String, slug: String)) -> Shortcut {
        let fetch = UUID().uuidString
        let url = "\(base)/api/screens/\(screen.slug)/toggle?key=\(key)"
        return Shortcut(name: toggleName, workflow: workflow(actions: [
            fetchAction(uuid: fetch, url: url)
        ] + show(key: "power", from: fetch, before: "Monitor ")))
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

    /// Get `key` from the reply and show it after `before` (Siri speaks it).
    private static func show(key: String, from fetch: String, before: String) -> [[String: Any]] {
        let value = UUID().uuidString
        return [
            [
                "WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey",
                "WFWorkflowActionParameters": [
                    "UUID": value,
                    "WFDictionaryKey": key,
                    "WFInput": [
                        "Value": output(fetch, "Contents of URL"),
                        "WFSerializationType": "WFTextTokenAttachment"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "WFWorkflowActionIdentifier": "is.workflow.actions.showresult",
                "WFWorkflowActionParameters": [
                    "Text": tokenString(before: before, output: (value, "Dictionary Value"), after: "")
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
            if text.localizedCaseInsensitiveContains("iCloud") {
                // Signing needs an Apple Account; the other mode won't help.
                return .failure(Failure(message: "Sign in to iCloud on this Mac (System Settings → your name), then try again."))
            }
        }
        return .failure(Failure(message: lastError))
    }
}
