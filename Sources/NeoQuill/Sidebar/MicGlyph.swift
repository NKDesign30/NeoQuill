import SwiftUI

// 24x24 Tile mit Mic-Glyph. Tertiary by default → emerald wenn aktiv → rot wenn recording.

struct MicGlyph: View {
    let active: Bool
    let recording: Bool
    var accent: Color = Neon.brandPrimary

    private var fg: Color {
        if recording { return Neon.recordingDot }
        return active ? accent : Neon.textTertiary
    }

    private var bg: Color {
        active ? accent.opacity(0.10) : Color.white.opacity(0.04)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
            .fill(bg)
            .frame(width: 24, height: 24)
            .overlay(
                GlyphView(name: .mic, size: 12, weight: .semibold, color: fg)
            )
    }
}
