import SwiftUI

// Karte mit Mono-Label-Pill links + Body-Text. Tone bestimmt Farbe (brand/warning/info).

struct HighlightRow: View {
    let highlight: Highlight
    var accent: Color = Neon.brandPrimary

    private var color: Color {
        switch highlight.tone {
        case .brand:   return accent
        case .warning: return Neon.statusWarning
        case .info:    return Neon.Speaker.indigo
        }
    }

    private var bg: Color {
        switch highlight.tone {
        case .brand:   return accent.opacity(0.10)
        case .warning: return Neon.statusWarning.opacity(0.10)
        case .info:    return Neon.Speaker.indigo.opacity(0.10)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(highlight.label.uppercased())
                .font(.neonMono(9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: 86)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(bg))
            Text(highlight.text)
                .font(.neonBody(14))
                .foregroundStyle(Neon.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }
}
