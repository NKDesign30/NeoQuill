import SwiftUI

// 01 — Willkommen. Editorial Display, vier Promise-Cards.
// Visual: konzentrische Ringe ums Quill-Icon mit Pulse-Glow.

struct WelcomeContent: View {
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Was gesagt wurde.")
                        .font(.neonDisplay(48))
                        .foregroundStyle(Neon.textPrimary)
                    Text("Was wichtig war.")
                        .font(.neonDisplay(48, italic: true))
                        .foregroundStyle(accent)
                }
            }
            Text("NeoQuill nimmt deine Meetings auf, transkribiert sie lokal mit WhisperKit und destilliert das Wichtige in Sekunden. Lass uns die Einrichtung in einer Minute durchgehen.")
                .font(.neonAlt(15))
                .foregroundStyle(Neon.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: 460, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                PromiseCard(symbol: "mic.fill", title: "Lokal",
                            subtitle: "WhisperKit ANE — kein Cloud-Upload", accent: accent)
                PromiseCard(symbol: "sparkles", title: "Klar",
                            subtitle: "Claude destilliert TL;DR & Tasks", accent: accent)
                PromiseCard(symbol: "checkmark.square", title: "Strukturiert",
                            subtitle: "Aktionspunkte, Kapitel, Highlights", accent: accent)
                PromiseCard(symbol: "magnifyingglass", title: "Auffindbar",
                            subtitle: "Volltextsuche, Mono-Zeitstempel", accent: accent)
            }
            .frame(maxWidth: 460)
        }
    }
}

struct WelcomeVisual: View {
    let accent: Color

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(accent.opacity([0.27, 0.19, 0.13, 0.08][i]), lineWidth: 0.5)
                    .padding(CGFloat(i) * 30)
            }
            // Pulse-Glow
            Circle()
                .fill(accent.opacity(0.27))
                .padding(90)
                .blur(radius: 22)
            // Icon-Container
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(hex: 0x242422))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(accent.opacity(0.35), lineWidth: 0.5)
                )
                .frame(width: 96, height: 96)
                .overlay(
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(accent)
                )
                .shadow(color: accent.opacity(0.2), radius: 40)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
            // Eyebrow
            VStack {
                Spacer()
                Text("NEOQUILL · v1.0 · MAI 2026")
                    .font(.neonMono(10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(Neon.textTertiary)
                    .padding(.top, 12)
            }
        }
        .frame(width: 280, height: 280)
    }
}
