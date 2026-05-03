import SwiftUI

// 02 — Mikrofon. Permission-Status-Card + Device-Picker.
// Visual: Mic-Orb mit pulsierenden Ringen wenn granted, Mini-Live-Bars unten.

struct MicrophoneContent: View {
    @ObservedObject var state: OnboardingState
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            OnboardingHeading(
                title: "Quill braucht ein Ohr.",
                lead: "Wir brauchen Zugriff auf dein Mikrofon und auf System-Audio, damit Online-Meetings beidseitig aufgenommen werden können. Alles bleibt auf deinem Mac.",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingFormLabel(text: "EINGABEGERÄT")
                    Picker("", selection: $state.selectedMicId) {
                        Text("Standard (auto)").tag("")
                        ForEach(state.availableMics, id: \.id) { mic in
                            Text(mic.name).tag(mic.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(height: 44)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                    )
                }

                permissionCard
            }
            .frame(maxWidth: 460)
        }
    }

    private var permissionCard: some View {
        let granted = state.micStatus == .granted
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(granted ? accent : Color.white.opacity(0.04))
                    .overlay(
                        Circle().stroke(granted ? accent : Neon.strokeDefault, lineWidth: 0.5)
                    )
                Image(systemName: granted ? "checkmark" : "mic")
                    .font(.system(size: 11, weight: granted ? .bold : .regular))
                    .foregroundStyle(granted ? .white : Neon.textTertiary)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(granted ? "Mikrofon-Zugriff gewährt" : "Mikrofon-Zugriff ausstehend")
                    .font(.neonBody(13, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                Text(granted
                     ? "Quill kann jetzt Eingangs- und System-Audio aufnehmen."
                     : "macOS fragt einmal — die Audiodaten verlassen deinen Mac nie.")
                    .font(.neonBody(11))
                    .foregroundStyle(Neon.textTertiary)
            }
            Spacer(minLength: 8)
            Text(granted ? "● ERLAUBT" : "○ AUSSTEHEND")
                .font(.neonMono(9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(granted ? accent : Neon.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? accent.opacity(0.08) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(granted ? accent.opacity(0.25) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }
}

struct MicVisual: View {
    let accent: Color
    let granted: Bool

    var body: some View {
        ZStack {
            if granted {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(accent.opacity(0.25), lineWidth: 0.5)
                        .padding(CGFloat(60 - i * 30))
                        .modifier(PulseRingModifier(delay: Double(i) * 0.5))
                }
            }
            Circle()
                .fill(granted ? accent.opacity(0.12) : Color.white.opacity(0.03))
                .overlay(
                    Circle().stroke(granted ? accent.opacity(0.4) : Neon.strokeHairline, lineWidth: 0.5)
                )
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: granted ? "mic.fill" : "mic")
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(granted ? accent : Neon.textTertiary)
                )
                .shadow(color: granted ? accent.opacity(0.25) : .clear, radius: 30)

            // Live-Bars unter dem Orb
            VStack {
                Spacer()
                MicLiveBars(accent: accent, active: granted)
                    .frame(height: 32)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: 280, height: 280)
    }
}

struct PulseRingModifier: ViewModifier {
    let delay: Double
    @State private var phase: Double = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 + phase * 0.6)
            .opacity(0.7 - phase * 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(delay)) {
                    phase = 1
                }
            }
    }
}

struct MicLiveBars: View {
    let accent: Color
    let active: Bool
    @State private var tick: Int = 0

    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()
    private let barCount = 32

    var body: some View {
        GeometryReader { geo in
            let totalSpacing: CGFloat = CGFloat(barCount - 1) * 3
            let barWidth = max(3, (geo.size.width - totalSpacing) / CGFloat(barCount))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(for: i)
                    Capsule()
                        .fill(active ? accent : Neon.textTertiary.opacity(0.35))
                        .frame(width: barWidth, height: max(3, h * geo.size.height))
                        .opacity(active ? 0.55 + h * 0.45 : 0.35)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(timer) { _ in
            if active { tick &+= 1 }
        }
    }

    private func barHeight(for i: Int) -> CGFloat {
        guard active else { return 0.18 }
        let a = sin(Double(i + tick) * 0.32) * 0.5 + cos(Double(i + tick) * 0.5 * 0.18) * 0.4
        return CGFloat(0.18 + abs(a) * 0.6)
    }
}
