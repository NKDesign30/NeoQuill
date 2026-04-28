import SwiftUI

// Toolbar-Button: nur Icon (28x28) ODER Icon + Label (28h, auto-width).

struct ToolbarButton: View {
    let icon: Glyph.Name
    var label: String? = nil
    var active: Bool = false
    var accent: Color = Neon.brandPrimary
    var action: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                GlyphView(name: icon, size: 14, color: foreground)
                if let label {
                    Text(label)
                        .font(.neonBodyButton)
                        .foregroundStyle(foreground)
                }
            }
            .padding(.horizontal, label == nil ? 0 : 10)
            .frame(width: label == nil ? 28 : nil, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Neon.Duration.fast), value: hovering)
    }

    private var foreground: Color {
        active ? (accent) : Neon.textSecondary
    }

    private var background: Color {
        if hovering { return Color.white.opacity(0.06) }
        if active   { return Color.white.opacity(0.04) }
        return .clear
    }
}
