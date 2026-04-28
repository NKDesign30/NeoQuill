import SwiftUI

// Keyboard-Hint Pill — Mono, hairline border, transparenter Inhalt.

struct Kbd: View {
    let symbols: [String]

    init(_ symbols: String...) { self.symbols = symbols }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.neonMono(10))
                    .foregroundStyle(Neon.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                    )
            }
        }
    }
}
