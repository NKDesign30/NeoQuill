import SwiftUI

// Frosted-Glass Pill am unteren Bildrand: pulsing Dot + Timer + MiniBars + Stop-Button.

struct FloatingPill: View {

    let elapsed: Int
    var onStop: () -> Void = {}

    @State private var breathe = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Neon.recordingDot)
                .frame(width: 8, height: 8)
                .opacity(breathe ? 0.45 : 1.0)
                .scaleEffect(breathe ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: breathe)

            Text(AudioPlayer.formatted(seconds: elapsed))
                .font(.neonMono(12, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
                .monospacedDigit()

            MiniBars()

            Button(action: onStop) {
                HStack(spacing: 6) {
                    GlyphView(name: .stop, size: 10, color: .white)
                    Text("Stoppen")
                        .font(.neonBody(12, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Neon.recordingDot))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: Neon.hairlineWidth))
        .scaleEffect(breathe ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathe)
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        .onAppear { breathe = true }
    }
}
