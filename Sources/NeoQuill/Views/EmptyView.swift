import SwiftUI

// Refined Empty: 96px Quill-Glyph, Editorial-Headline, 3 ChipButtons, CTA, Footer-Hint.

struct EmptyView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()
                glyph
                    .padding(.bottom, 28)
                Text("Willkommen bei NeoQuill")
                    .font(.neonDisplay(32))
                    .foregroundStyle(Neon.textPrimary)
                Text("Wähle ein Meeting aus der Sidebar oder starte eine neue Aufnahme.")
                    .font(.neonBody(14))
                    .foregroundStyle(Neon.textSecondary)
                    .frame(maxWidth: 380)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    ChipButton(icon: .sparkles, label: "WhisperKit ANE", tone: .brand)
                    ChipButton(icon: .mic,      label: "Built-in Mic",   tone: .info)
                    ChipButton(icon: .flame,    label: "Claude Analyse", tone: .warning)
                }
                .padding(.top, 28)

                cta.padding(.top, 32)
                Spacer()
            }
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()
                Text("WAS GESAGT WURDE. WAS WICHTIG WAR.")
                    .font(.neonMono(11))
                    .tracking(1.6)
                    .foregroundStyle(Neon.textQuaternary)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.03))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            GlyphView(name: .waveform, size: 36, weight: .light, color: Neon.textTertiary)
        }
        .frame(width: 96, height: 96)
    }

    private var cta: some View {
        Button {
            state.startRecording()
        } label: {
            HStack(spacing: 8) {
                GlyphView(name: .mic, size: 14, weight: .semibold, color: .white)
                Text("Aufnahme starten")
                    .font(.neonBodyButton)
                    .foregroundStyle(.white)
                Kbd("⌥", "R")
                    .opacity(0.7)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 16)
            .padding(.trailing, 20)
            .frame(height: 38)
            .background(
                Capsule().fill(Neon.brandPrimary)
            )
            .overlay(
                Capsule()
                    .stroke(Neon.brandPrimary.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.40), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: [.option])
    }
}
