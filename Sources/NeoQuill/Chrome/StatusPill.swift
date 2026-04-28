import SwiftUI

// Pill: "Bereit" (emerald, ruhig) ↔ "Aufnahme läuft" (rot, atmend).

struct StatusPill: View {
    let recording: Bool
    let label: String

    @State private var pulsate = false

    private var dotColor: Color { recording ? Neon.recordingDot : Neon.brandPrimary }
    private var textColor: Color { recording ? Neon.recordingDotBright : Color(hex: 0x5ED0A0) }
    private var background: Color {
        recording ? Color(hex: 0xFF6259, alpha: 0.10) : Color(hex: 0x2EAB73, alpha: 0.10)
    }
    private var border: Color {
        recording ? Color(hex: 0xFF6259, alpha: 0.30) : Color(hex: 0x2EAB73, alpha: 0.30)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsate && recording ? 1.4 : 1.0)
                .opacity(pulsate && recording ? 0.45 : 1.0)
                .animation(
                    recording
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsate
                )
            Text(label)
                .font(.neonEyebrowSm)
                .tracking(0.4)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 0)
        .frame(height: 22)
        .background(
            Capsule().fill(background)
        )
        .overlay(Capsule().stroke(border, lineWidth: Neon.hairlineWidth))
        .onAppear { if recording { pulsate = true } }
        .onChange(of: recording) { _, isOn in pulsate = isOn }
    }
}
