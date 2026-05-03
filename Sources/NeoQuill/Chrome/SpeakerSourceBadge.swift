import SwiftUI

// Kleine Lable + Confidence-Anzeige für eine TranscriptLine. Macht sichtbar
// woher der Speaker-Name stammt (Caption/Plattform/Diarization/...) und wie
// sicher das System ist. Bewusst dezent — soll Lesefluss nicht stoeren.

struct SpeakerSourceBadge: View {
    let source: SpeakerIdentitySource
    let confidence: Double

    var body: some View {
        HStack(spacing: 5) {
            ConfidenceDot(confidence: confidence)
            Text(label)
                .font(.neonMono(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(backgroundColor)
        )
        .overlay(
            Capsule().stroke(borderColor, lineWidth: Neon.hairlineWidth)
        )
        .help(tooltip)
    }

    private var label: String {
        switch source {
        case .microphoneOwner: return "MIKRO"
        case .caption:         return "CAPTION"
        case .platformApi:     return "PLATTFORM"
        case .knownVoice:      return "BEKANNT"
        case .diarization:     return "ERKANNT"
        case .manual:          return "MANUELL"
        case .unknown:         return "?"
        }
    }

    private var tooltip: String {
        let confidencePercent = Int((confidence * 100).rounded())
        let sourceText: String
        switch source {
        case .microphoneOwner: sourceText = "Aus dem Mikrofon-Stream — das bist du."
        case .caption:         sourceText = "Live-Caption der Meeting-App."
        case .platformApi:     sourceText = "Offizielles Transkript der Plattform."
        case .knownVoice:      sourceText = "Stimme aus früheren Meetings wiedererkannt."
        case .diarization:     sourceText = "Lokale Diarization (anonym, ohne Namen)."
        case .manual:          sourceText = "Du hast diesen Speaker manuell gelabelt."
        case .unknown:         sourceText = "Quelle unbekannt."
        }
        return "\(sourceText) Confidence: \(confidencePercent)%"
    }

    private var backgroundColor: Color {
        switch source {
        case .microphoneOwner, .manual, .knownVoice:
            return Neon.brandPrimary.opacity(0.12)
        case .platformApi, .caption:
            return Color.white.opacity(0.05)
        case .diarization:
            return Color.white.opacity(0.03)
        case .unknown:
            return Color.white.opacity(0.02)
        }
    }

    private var borderColor: Color {
        switch source {
        case .microphoneOwner, .manual, .knownVoice:
            return Neon.brandPrimary.opacity(0.35)
        default:
            return Neon.strokeHairline
        }
    }

    private var textColor: Color {
        switch source {
        case .microphoneOwner, .manual, .knownVoice:
            return Neon.brandPrimary
        case .platformApi, .caption, .diarization:
            return Neon.textTertiary
        case .unknown:
            return Neon.textTertiary.opacity(0.6)
        }
    }
}

struct ConfidenceDot: View {
    let confidence: Double
    var diameter: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
    }

    private var color: Color {
        let clamped = max(0, min(1, confidence))
        if clamped >= 0.85 { return Color(hex: 0x2EAB73) }
        if clamped >= 0.6  { return Color(hex: 0xFFB340) }
        return Color(hex: 0xFF6259)
    }
}
