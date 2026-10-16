/// Combined brightness: one 0...1 scale per screen, like BetterDisplay's
/// "Brightness (Combined)".
///
/// For a monitor with DDC/CI brightness, the top of the scale is its real
/// backlight; below `hardwareFloor` the backlight is at its minimum and
/// software dimming takes over, so it can go darker than the monitor allows.
/// A monitor without DDC/CI uses software dimming across the whole scale.
/// Software dimming stops at `minimumSoftwareLevel`, so a screen at 0% is
/// very dark but never fully black.
enum BrightnessCurve {
    /// Share of the scale (from the bottom) given to software dimming on DDC monitors.
    static let hardwareFloor = 0.2
    /// The darkest software dimming level (gamma scale).
    static let minimumSoftwareLevel = 0.1

    /// Hardware fraction (0...1) and software dimming level for a combined level.
    static func split(_ level: Double) -> (hardware: Double, software: Double) {
        let level = clamp(level)
        if level >= hardwareFloor {
            return ((level - hardwareFloor) / (1 - hardwareFloor), 1)
        }
        return (0, softwareLevel(forDimming: level / hardwareFloor))
    }

    /// The combined level of a DDC monitor.
    static func combined(hardware: Double, software: Double) -> Double {
        if software >= 0.999 {
            return hardwareFloor + clamp(hardware) * (1 - hardwareFloor)
        }
        return dimming(forSoftwareLevel: software) * hardwareFloor
    }

    /// Software-only monitors: gamma level for a 0...1 dimming position, and back.
    static func softwareLevel(forDimming position: Double) -> Double {
        minimumSoftwareLevel + (1 - minimumSoftwareLevel) * clamp(position)
    }

    static func dimming(forSoftwareLevel level: Double) -> Double {
        clamp((level - minimumSoftwareLevel) / (1 - minimumSoftwareLevel))
    }

    /// One key press on the system's 16-step scale (64 steps when fine).
    static func step(_ level: Double, up: Bool, fine: Bool) -> Double {
        let steps = fine ? 64.0 : 16.0
        return clamp(((level * steps).rounded() + (up ? 1 : -1)) / steps)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
