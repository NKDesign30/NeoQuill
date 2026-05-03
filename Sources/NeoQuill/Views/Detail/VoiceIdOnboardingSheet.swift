import SwiftUI

// 3-Phasen-Sheet fuer Voice-ID Onboarding. Zeigt Standard-Satz zum Vorlesen,
// Live-Mikropegel waehrend der Aufnahme, am Ende Bestaetigung oder Fehlerbild.

struct VoiceIdOnboardingSheet: View {

    @ObservedObject var enrollment: VoiceIdEnrollmentService
    var onDismiss: () -> Void

    private static let prompt = "Hi, ich bin \(LocalSpeakerProfile.displayName). Diese Aufnahme nutzt NeoQuill, um meine Stimme in zukuenftigen Meetings automatisch zu erkennen — ohne dass ich mich extra einloggen muss."

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            Group {
                switch enrollment.phase {
                case .idle:
                    explainerCard
                case .requestingPermission:
                    statusCard(symbol: "mic.fill", title: "Mikrofon-Zugriff anfragen…",
                               subtitle: "Bitte bestaetige in macOS, falls ein Dialog erscheint.")
                case .recording(let secondsRemaining):
                    recordingCard(remaining: secondsRemaining)
                case .processing:
                    statusCard(symbol: "waveform.path.ecg", title: "Stimm-Embedding wird berechnet…",
                               subtitle: "Dauert nur ein paar Sekunden.")
                case .saved:
                    successCard
                case .failed(let message):
                    failureCard(message: message)
                }
            }
            .frame(minHeight: 220)

            footer
        }
        .padding(28)
        .frame(width: 520)
        .background(Neon.surfaceBackground)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stimme einrichten")
                .font(.neonBody(20, weight: .semibold))
                .foregroundStyle(Neon.textPrimary)
            Text("8 Sekunden vorlesen — danach erkennt NeoQuill deine Stimme automatisch in Meetings.")
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
        }
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vorlage zum Vorlesen")
                .font(.neonMono(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Neon.textTertiary)
            Text(Self.prompt)
                .font(.neonBody(15))
                .foregroundStyle(Neon.textPrimary)
                .lineSpacing(4)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Neon.brandPrimary)
                Text("Aufnahme bleibt lokal — nur das Embedding (256 Zahlen) wird gespeichert.")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textTertiary)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private func recordingCard(remaining: Double) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aufnahme laeuft…")
                    .font(.neonBody(16, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                Spacer()
                Text(String(format: "%.1fs", remaining))
                    .font(.neonMono(13, weight: .semibold))
                    .foregroundStyle(Neon.brandPrimary)
                    .monospacedDigit()
            }

            Text(Self.prompt)
                .font(.neonBody(14))
                .foregroundStyle(Neon.textSecondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let progress = max(0, min(1, 1 - remaining / VoiceIdEnrollmentService.recordingDuration))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.05))
                        Capsule().fill(Neon.brandPrimary).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)

                MeterBar(level: enrollment.meterLevel)
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Neon.brandPrimary)
                    .font(.system(size: 22))
                Text("Stimme gespeichert")
                    .font(.neonBody(16, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
            }
            Text("Ab jetzt ersetzt NeoQuill anonyme `S1`-Marker mit \(LocalSpeakerProfile.displayName) — sobald deine Stimme im Mic-Stream erkannt wird.")
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private func failureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Neon.statusError)
                    .font(.system(size: 22))
                Text("Aufnahme fehlgeschlagen")
                    .font(.neonBody(16, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
            }
            Text(message)
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
                .lineSpacing(3)
        }
        .padding(18)
        .background(cardBackground)
    }

    private func statusCard(symbol: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(Neon.brandPrimary)
                    .font(.system(size: 18))
                Text(title)
                    .font(.neonBody(15, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
            }
            Text(subtitle)
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Abbrechen") {
                enrollment.cancelEnrollment()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)

            Spacer()

            switch enrollment.phase {
            case .idle, .failed:
                Button("Aufnahme starten") {
                    Task { await enrollment.startEnrollment() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            case .saved:
                Button("Fertig") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            default:
                EmptyView()
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
    }
}

private struct MeterBar: View {
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<24, id: \.self) { idx in
                Capsule()
                    .fill(color(for: idx))
                    .frame(width: 4, height: barHeight(for: idx))
            }
        }
        .frame(height: 18)
    }

    private func barHeight(for idx: Int) -> CGFloat {
        let normalized = CGFloat(level)
        let activeBars = Int(normalized * 24)
        return idx < activeBars ? CGFloat.random(in: 6...18) : 4
    }

    private func color(for idx: Int) -> Color {
        let normalized = Double(level)
        let activeBars = Int(normalized * 24)
        if idx >= activeBars { return Color.white.opacity(0.08) }
        if idx > 18          { return Neon.statusError.opacity(0.85) }
        if idx > 14          { return Color(hex: 0xFFB340) }
        return Neon.brandPrimary
    }
}
