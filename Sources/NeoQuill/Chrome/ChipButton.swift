import SwiftUI

// Status-Chip: kleines Glyph in Akzentfarbe + Label sekundär. 28h, hairline.

struct ChipButton: View {
    enum Tone { case brand, info, warning, error }

    let icon: Glyph.Name
    let label: String
    var tone: Tone = .info

    private var accent: Color {
        switch tone {
        case .brand:   return Neon.brandPrimary
        case .info:    return Neon.Speaker.indigo
        case .warning: return Neon.statusWarning
        case .error:   return Neon.statusError
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            GlyphView(name: icon, size: 11, color: accent)
            Text(label)
                .font(.neonBodySm)
                .foregroundStyle(Neon.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(
            Capsule().fill(Color.white.opacity(0.04))
        )
        .overlay(Capsule().stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth))
    }
}
