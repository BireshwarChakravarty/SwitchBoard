/// What a factory-reset command achieved, judged from the monitor's settings
/// read before and after. Both reset commands are optional in the DDC/CI
/// standard, so a monitor may accept the message and do nothing.
enum FactoryRestoreOutcome: Equatable {
    /// The command didn't reach the monitor.
    case unreachable
    /// Sent, but the monitor didn't report its settings afterwards.
    case unconfirmed
    /// Settings changed; the summary shows the new values.
    case restored(summary: String)
    /// Nothing changed; the summary shows the unchanged values.
    case ignored(summary: String)
    /// No earlier values to compare with; the summary shows the values now.
    case readBack(summary: String)

    static func evaluate(sent: Bool, before: [UInt8: VCPValue], after: [UInt8: VCPValue]) -> Self {
        guard sent else { return .unreachable }
        guard !after.isEmpty else { return .unconfirmed }
        let summary = summary(of: after)
        guard !before.isEmpty else { return .readBack(summary: summary) }
        let changed = after.contains { vcp, value in before[vcp]?.current != value.current }
        return changed ? .restored(summary: summary) : .ignored(summary: summary)
    }

    /// "Brightness 80% · Contrast 50%" (only the values present).
    static func summary(of values: [UInt8: VCPValue]) -> String {
        let named: [(UInt8, String)] = [(VCP.brightness, "Brightness"), (VCP.contrast, "Contrast")]
        return named.compactMap { vcp, name -> String? in
            guard let value = values[vcp], value.max > 0 else { return nil }
            return "\(name) \(Int((Double(value.current) / Double(value.max) * 100).rounded()))%"
        }.joined(separator: " · ")
    }

    /// The status-line message, and whether it's a problem (shown in orange).
    var message: (text: String, isProblem: Bool) {
        switch self {
        case .unreachable:
            ("Couldn't reach the monitor over DDC/CI", true)
        case .unconfirmed:
            ("Sent · the monitor didn't report its settings back", false)
        case .restored(let summary):
            (summary.isEmpty ? "Factory settings restored" : "Restored · \(summary)", false)
        case .ignored(let summary):
            (summary.isEmpty ? "The monitor ignored the reset" : "Monitor ignored it · \(summary)", true)
        case .readBack(let summary):
            (summary.isEmpty ? "Reset sent" : "Reset sent · now \(summary)", false)
        }
    }
}
