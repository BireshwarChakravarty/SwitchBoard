import SwiftUI
import AppKit

/// Layout constants shared by the menu's views.
enum Metrics {
    static let width: CGFloat = 340
    static let cardRadius: CGFloat = 14
    static let tile: CGFloat = 30
}

/// Switchboard's look, "Signal": the system's own colours and materials, and
/// one warm amber for what's on, like a power light.
enum Theme {
    /// #F5A524: switches that are on, filled sliders, lit screen tiles.
    static let signal = Color(red: 0.961, green: 0.647, blue: 0.141)
    /// #1C1D21: symbols and text drawn on Signal.
    static let onSignal = Color(red: 0.11, green: 0.114, blue: 0.129)
    /// The selected screen's card and other grouped areas.
    static let card = Color.primary.opacity(0.06)
    /// Empty slider tracks and screen tiles that are off.
    static let track = Color.primary.opacity(0.14)
}

/// A screen's symbol on a rounded tile: lit in Signal amber while the screen
/// is on, grey while it's off.
struct ScreenTile: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isOn ? Theme.onSignal : Color.secondary)
            .frame(width: Metrics.tile, height: Metrics.tile)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Theme.signal) : AnyShapeStyle(Theme.track))
            )
            .animation(.snappy(duration: 0.2), value: isOn)
    }
}

/// A plain label with a small switch at the trailing edge.
struct SwitchRow: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// A titled control: "Brightness   65%" above its slider.
struct ControlBlock<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// A slim slider: a thin track filled in Signal amber, with a white knob.
/// Drag or click anywhere on it; VoiceOver can adjust it with
/// increment/decrement.
struct LevelSlider: View {
    let value: Double
    var steps: Int?
    let onChange: (Double) -> Void
    var onCommit: () -> Void = {}

    private static let knob: CGFloat = 16
    private static let track: CGFloat = 6

    init(value: Double, steps: Int? = nil,
         onChange: @escaping (Double) -> Void, onCommit: @escaping () -> Void = {}) {
        self.value = value
        self.steps = steps
        self.onChange = onChange
        self.onCommit = onCommit
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let offset = (width - Self.knob) * min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                    .frame(height: Self.track)
                Capsule()
                    .fill(Theme.signal)
                    .frame(width: offset + Self.knob / 2, height: Self.track)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: Self.knob, height: Self.knob)
                    .offset(x: offset)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = (drag.location.x - Self.knob / 2) / max(width - Self.knob, 1)
                        onChange(snap(position))
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: 20)
        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: value)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((value * 100).rounded())) percent"))
        .accessibilityAdjustableAction { direction in
            let step = 1 / Double(max((steps ?? 17) - 1, 1))
            switch direction {
            case .increment: onChange(snap(value + step))
            case .decrement: onChange(snap(value - step))
            @unknown default: return
            }
            onCommit()
        }
    }

    private func snap(_ position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        guard let steps, steps > 1 else { return clamped }
        let last = Double(steps - 1)
        return (clamped * last).rounded() / last
    }
}

/// Whether the pointer is over a view. A class, because the menu avoids
/// @State (see SwitchboardApp's design notes).
final class HoverState: ObservableObject {
    @Published var isHovered = false
}

/// A row at the foot of the menu that looks and behaves like a menu item:
/// highlighted under the pointer, with its keyboard shortcut on the right.
struct MenuRowButton: View {
    let title: String
    let key: KeyEquivalent
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text("⌘\(String(key.character).uppercased())")
                    .foregroundStyle(hover.isHovered ? Theme.onSignal.opacity(0.7) : Color.secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(hover.isHovered ? Theme.onSignal : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover.isHovered ? Theme.signal : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key)
        .onHover { hover.isHovered = $0 }
    }
}

/// A small outlined label, e.g. "MAIN".
struct Tag: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .help(help)
    }
}
