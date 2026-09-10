import SwiftUI

struct PrimaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DaylightButtonBody(label: configuration.label, isPressed: configuration.isPressed, variant: .primary)
    }
}

struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DaylightButtonBody(label: configuration.label, isPressed: configuration.isPressed, variant: .secondary)
    }
}

struct DaylightIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DaylightButtonBody(label: configuration.label, isPressed: configuration.isPressed, variant: .icon)
    }
}

struct DaylightCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(DaylightTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DaylightTheme.hairline, lineWidth: 1)
            }
    }
}

private enum DaylightButtonVariant {
    case primary
    case secondary
    case icon

    var minimumHeight: CGFloat {
        self == .icon ? DaylightTheme.minimumTarget : DaylightTheme.primaryHeight
    }

    var normalBackground: Color {
        switch self {
        case .primary: DaylightTheme.action
        case .secondary, .icon: DaylightTheme.surface
        }
    }

    var hoveredBackground: Color {
        switch self {
        case .primary: DaylightTheme.action.opacity(0.86)
        case .secondary, .icon: DaylightTheme.canvas
        }
    }

    var pressedBackground: Color {
        switch self {
        case .primary: DaylightTheme.action.opacity(0.72)
        case .secondary, .icon: DaylightTheme.hairline
        }
    }

    var disabledBackground: Color {
        self == .primary ? DaylightTheme.slate.opacity(0.36) : DaylightTheme.hairline
    }

    var foreground: Color {
        self == .primary ? DaylightTheme.surface : DaylightTheme.ink
    }

    var disabledForeground: Color { DaylightTheme.slate }

    var shape: Capsule { Capsule() }
}

private struct DaylightButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let variant: DaylightButtonVariant

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    private var background: Color {
        guard isEnabled else { return variant.disabledBackground }
        if isPressed { return variant.pressedBackground }
        return isHovered ? variant.hoveredBackground : variant.normalBackground
    }

    private var foreground: Color {
        isEnabled ? variant.foreground : variant.disabledForeground
    }

    var body: some View {
        label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(minWidth: DaylightTheme.minimumTarget, minHeight: variant.minimumHeight)
            .padding(.horizontal, variant == .icon ? 0 : 16)
            .background(background, in: variant.shape)
            .overlay {
                variant.shape
                    .stroke(
                        isFocused && variant == .primary ? DaylightTheme.surface
                            : isFocused ? DaylightTheme.action : DaylightTheme.hairline,
                        lineWidth: isFocused ? 2 : 1
                    )
            }
            .contentShape(variant.shape)
            .scaleEffect(isPressed && isEnabled && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(isPressed ? .isButton : [])
    }
}
