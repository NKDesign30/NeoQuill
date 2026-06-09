import SwiftUI

// 03 — Stimme & Name. Name + Org Input, Voice-Sample-Card.
// Visual: Speaker-Card mit Stimm-Fingerprint (Tonhöhe/Tempo/Sprache).

struct VoiceContent: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var enrollment: VoiceIdEnrollmentService
    let accent: Color

    private let phrase = "\u{201E}Was gesagt wurde, was wichtig war.\u{201C}"

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            OnboardingHeading(
                title: "Damit Quill dich erkennt.",
                lead: "Sprich einen Satz ein — Quill lernt deine Stimme und unterscheidet dich später automatisch von anderen Teilnehmern. Der Sample bleibt lokal.",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingFormLabel(text: "DEIN NAME")
                    OnboardingTextField(text: $state.name, placeholder: "Vor- und Nachname", accent: accent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    OnboardingFormLabel(text: "STIMM-SAMPLE", hint: "≈ 8 Sekunden, deutsch oder englisch")
                    voiceSampleCard
                }
            }
            .frame(maxWidth: 460)
        }
    }

    private var voiceSampleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(phrase)
                .font(.neonDisplay(22, italic: true))
                .foregroundStyle(sampleStateColor)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            VoiceSampleBars(accent: accent, isActive: isRecording, isDone: isDone)
                .frame(height: 36)

            HStack(spacing: 12) {
                Button(action: handleSampleTap) {
                    HStack(spacing: 6) {
                        Image(systemName: sampleButtonIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(sampleButtonLabel)
                            .font(.neonBody(12, weight: .medium))
                    }
                    .foregroundStyle(isRecording ? .white : accent)
                    .padding(.leading, 10)
                    .padding(.trailing, 14)
                    .frame(height: 32)
                    .background(
                        Capsule().fill(isRecording ? Color(hex: 0xFF6259) : accent.opacity(0.12))
                    )
                    .overlay(
                        Capsule().stroke(isRecording ? Color(hex: 0xFF6259) : accent.opacity(0.4), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                hintLabel
                Spacer()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isRecording ? accent.opacity(0.4) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }

    private var hintLabel: some View {
        HStack(spacing: 6) {
            if isRecording {
                Circle()
                    .fill(Color(hex: 0xFF6259))
                    .frame(width: 6, height: 6)
                    .modifier(BlinkModifier())
            } else if isDone {
                Text("●").foregroundStyle(accent)
            }
            Text(hintText)
                .font(.neonMono(11))
                .foregroundStyle(isDone ? accent : Neon.textTertiary)
        }
    }

    private var isRecording: Bool {
        if case .recording = enrollment.phase { return true }
        return false
    }

    private var isDone: Bool {
        if case .saved = enrollment.phase { return true }
        return false
    }

    private var sampleStateColor: Color {
        isDone ? Neon.textPrimary : Neon.textSecondary
    }

    private var sampleButtonIcon: String {
        if isRecording { return "stop.fill" }
        return "mic"
    }

    private var sampleButtonLabel: String {
        if isRecording { return "Aufnahme stoppen" }
        if isDone      { return "Erneut aufnehmen" }
        return "Aufnahme starten"
    }

    private var hintText: String {
        switch enrollment.phase {
        case .recording: return "Hört zu… sprich jetzt"
        case .saved:     return "Sample gespeichert · 8 s"
        case .processing: return "Verarbeite Sample…"
        case .requestingPermission: return "Mikrofon-Zugriff anfragen…"
        case .failed(let m): return m
        case .idle:      return "Drücke und sprich den Satz oben"
        }
    }

    private func handleSampleTap() {
        switch enrollment.phase {
        case .recording, .processing, .requestingPermission:
            enrollment.cancelEnrollment()
        default:
            Task { await enrollment.startEnrollment() }
        }
    }
}

struct VoiceVisual: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var enrollment: VoiceIdEnrollmentService
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            speakerCard
            strangerCard
        }
        .frame(width: 340)
    }

    private var speakerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(initials: speakerInitials, color: accent, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.name.isEmpty ? "Niko Knez" : state.name)
                        .font(.neonBody(13, weight: .semibold))
                        .foregroundStyle(Neon.textPrimary)
                    Text("SPRECHER · DU")
                        .font(.neonMono(10))
                        .tracking(0.4)
                        .foregroundStyle(Neon.textTertiary)
                }
                Spacer()
                Text(isDone ? "● ERKANNT" : "○ LERNT")
                    .font(.neonMono(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isDone ? accent : Neon.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isDone ? accent.opacity(0.12) : Color.white.opacity(0.04))
                    )
            }

            Text("STIMMEN-FINGERPRINT")
                .font(.neonMono(10))
                .tracking(0.4)
                .foregroundStyle(Neon.textTertiary)

            VoiceSampleBars(accent: accent, isActive: isRecording, isDone: isDone)
                .frame(height: 44)

            HStack(spacing: 10) {
                fingerprintMetric(label: "TONHÖHE", value: "142 Hz")
                fingerprintMetric(label: "TEMPO",   value: "168 wpm")
                fingerprintMetric(label: "SPRACHE", value: state.language.uppercased())
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x242422).opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
    }

    private var strangerCard: some View {
        HStack(spacing: 10) {
            Avatar(initials: "?", color: Color.white.opacity(0.18), size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unbekannter Sprecher")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textSecondary)
                Text("WIRD IM MEETING ZUGEORDNET")
                    .font(.neonMono(10))
                    .tracking(0.4)
                    .foregroundStyle(Neon.textTertiary.opacity(0.6))
            }
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 13))
                .foregroundStyle(Neon.textTertiary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .opacity(0.7)
    }

    private func fingerprintMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.neonMono(9))
                .tracking(0.6)
                .foregroundStyle(Neon.textTertiary.opacity(0.6))
            Text(isDone || isRecording ? value : "——")
                .font(.neonMono(12))
                .foregroundStyle(isDone ? Neon.textPrimary : Neon.textTertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speakerInitials: String {
        let parts = state.name.split(separator: " ")
        let initials = parts.compactMap { $0.first.map(String.init) }.joined()
        if !initials.isEmpty { return String(initials.prefix(2)).uppercased() }
        return "ME"
    }

    private var isRecording: Bool {
        if case .recording = enrollment.phase { return true }
        return false
    }

    private var isDone: Bool {
        if case .saved = enrollment.phase { return true }
        return VoiceIdEnrollmentService.isEnrolled
    }
}

struct VoiceSampleBars: View {
    let accent: Color
    let isActive: Bool
    let isDone: Bool
    var barCount: Int = 56
    @State private var tick: Int = 0

    private let timer = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 3
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let barWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(for: i)
                    Capsule()
                        .fill(barColor(for: i))
                        .frame(width: barWidth, height: max(3, h * geo.size.height))
                        .opacity(isActive ? 0.55 + h * 0.45 : (isDone ? 0.9 : 0.4))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onReceive(timer) { _ in
            if isActive { tick &+= 1 }
        }
    }

    private func barHeight(for i: Int) -> CGFloat {
        if isDone {
            let seed = sin(Double(i) * 0.7) * 0.5 + cos(Double(i) * 0.31) * 0.4
            return CGFloat(0.18 + abs(seed) * 0.7)
        }
        if isActive {
            let a = sin(Double(i + tick) * 0.32) * 0.5 + cos(Double(i + tick) * 0.5 * 0.18) * 0.4
            return CGFloat(0.18 + abs(a) * 0.7)
        }
        return 0.14
    }

    private func barColor(for i: Int) -> Color {
        if isActive || isDone { return accent }
        return Color.white.opacity(0.14)
    }
}

struct BlinkModifier: ViewModifier {
    @State private var on: Bool = true
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
    }
}
