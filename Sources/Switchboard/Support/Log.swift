import os

/// Unified logging. Watch it live with:
///
///     log stream --level debug --predicate 'subsystem == "app.switchboard.Switchboard"'
///
/// Monitor names and DDC details aren't personal data, so they're logged as
/// public to keep bug reports useful.
enum Log {
    private static let subsystem = "app.switchboard.Switchboard"

    static let ddc = Logger(subsystem: subsystem, category: "ddc")
    static let display = Logger(subsystem: subsystem, category: "display")
    static let app = Logger(subsystem: subsystem, category: "app")
}
