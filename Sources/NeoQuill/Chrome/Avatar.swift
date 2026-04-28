import SwiftUI

// Initialen-Circle. Background = Speaker-Color, Text auf brand-deep für Kontrast.

struct Avatar: View {
    let initials: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.neonMono(max(9, size * 0.36), weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Neon.logoNight1)
            )
    }
}

// Stack der ersten drei Teilnehmer mit Überlappung.
struct ParticipantStack: View {
    let participants: [Participant]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(participants.prefix(4).enumerated()), id: \.element.id) { _, p in
                Avatar(initials: p.id, color: p.color, size: size)
                    .overlay(
                        Circle().stroke(Neon.surfaceBackground, lineWidth: 2)
                    )
            }
        }
    }
}
