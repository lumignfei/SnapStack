import SwiftUI

enum InterfaceStyle {
    // B · 冷灰蓝
    static let background = Color(red: 244 / 255.0, green: 246 / 255.0, blue: 249 / 255.0)
    static let ink = Color(red: 48 / 255.0, green: 58 / 255.0, blue: 73 / 255.0)
    static let muted = Color(red: 102 / 255.0, green: 116 / 255.0, blue: 135 / 255.0)
    static let accent = Color(red: 96 / 255.0, green: 124 / 255.0, blue: 155 / 255.0)
    static let accentBackground = Color(red: 229 / 255.0, green: 237 / 255.0, blue: 245 / 255.0)
    static let primaryButton = Color(red: 82 / 255.0, green: 111 / 255.0, blue: 144 / 255.0)
    static let line = accent.opacity(0.15)
}

struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(prominent ? Color.white : InterfaceStyle.primaryButton)
            .background(prominent ? InterfaceStyle.primaryButton : Color.white,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(InterfaceStyle.line))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.38)
    }
}

// Keep the entire label rectangle interactive, including hollow icons and gaps.
struct ToolbarHoverStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }
    private struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @StateObject private var hover = HoverState()
        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .fill(InterfaceStyle.ink.opacity(enabled ? (configuration.isPressed ? 0.12 : hover.value ? 0.065 : 0) : 0))
                    .allowsHitTesting(false))
                .onHover { hover.value = $0 }
                .animation(.easeOut(duration: 0.12), value: hover.value)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

private final class HoverState: ObservableObject {
    @Published var value = false
}
