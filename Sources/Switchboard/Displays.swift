import CoreGraphics

/// CoreGraphics display lists.
enum Displays {
    /// Every connected display, including mirrored ones and ones asleep.
    static func online() -> [CGDirectDisplayID] {
        list(CGGetOnlineDisplayList)
    }

    /// Displays macOS is currently drawing to.
    static func active() -> [CGDirectDisplayID] {
        list(CGGetActiveDisplayList)
    }

    private static func list(
        _ get: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard get(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard get(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
