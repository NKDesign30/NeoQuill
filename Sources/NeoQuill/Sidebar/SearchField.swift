import SwiftUI

// Sidebar-Search: 30h, hairline-border, focus-state mit emerald-Inset.

struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Suchen…"
    var accent: Color = Neon.brandPrimary

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            GlyphView(name: .search, size: 12, color: Neon.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.neonBody(13))
                .foregroundStyle(Neon.textPrimary)
                .focused($focused)
            if !focused {
                Kbd("⌘", "F")
            }
        }
        .padding(.horizontal, 8)
        .padding(.leading, 2)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                .fill(focused ? Color.white.opacity(0.06) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                .stroke(focused ? accent.opacity(0.6) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                .stroke(focused ? accent.opacity(0.35) : .clear, lineWidth: 1)
                .blendMode(.plusLighter)
        )
        .animation(.easeOut(duration: Neon.Duration.fast), value: focused)
    }
}
