import SwiftUI
import AppKit

/// Layout constants shared by the menu's views.
enum Metrics {
    static let width: CGFloat = 340
    static let cardRadius: CGFloat = 20
    static let cardInset: CGFloat = 6
    static let rowRadius: CGFloat = 14 // cardRadius - cardInset: concentric
    static let badge: CGFloat = 32
}

/// A plain label with a small switch at the trailing edge.
struct SwitchRow: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack {
            Text(title).font(.callout)
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            content()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// A Control Center–style slider: a thick capsule that fills from the left,
/// with its symbol inside. Drag or click anywhere on it; VoiceOver can adjust
/// it with increment/decrement.
struct PillSlider: View {
    let value: Double
    let symbol: String
    var steps: Int?
    let onChange: (Double) -> Void
    var onCommit: () -> Void = {}

    private static let height: CGFloat = 26

    init(value: Double, symbol: String, steps: Int? = nil,
         onChange: @escaping (Double) -> Void, onCommit: @escaping () -> Void = {}) {
        self.value = value
        self.symbol = symbol
        self.steps = steps
        self.onChange = onChange
        self.onCommit = onCommit
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fill = Self.height + (width - Self.height) * min(max(value, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.white)
                    .frame(width: fill)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .frame(width: Self.height, height: Self.height)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = (drag.location.x - Self.height / 2) / max(width - Self.height, 1)
                        onChange(snap(position))
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: Self.height)
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

/// A round glass icon button.
struct CircleButton: View {
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// A round symbol badge, filled with the accent colour when active.
struct IconBadge: View {
    let symbol: String
    let isActive: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .symbolEffect(.bounce, value: isActive)
            .frame(width: Metrics.badge, height: Metrics.badge)
            .background(
                Circle().fill(isActive ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary))
            )
            .animation(.snappy(duration: 0.2), value: isActive)
    }
}

/// A small capsule label, e.g. "Main".
struct Tag: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .help(help)
    }
}
