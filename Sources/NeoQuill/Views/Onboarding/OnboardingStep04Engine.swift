import SwiftUI

// 04 — KI-Engine. Zwei EngineCards (ANE / Cloud) + Claude-Toggle.
// Visual: Pipeline-Diagramm mit Mikrofon → Engine → Claude → Mediathek.

struct EngineContent: View {
    @ObservedObject var state: OnboardingState
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingHeading(
                title: "Wo soll Quill denken?",
                lead: "WhisperKit läuft auf der Apple Neural Engine — schnell, lokal, ohne Cloud. Cloud-Modelle sind genauer bei seltenen Sprachen, brauchen aber Internet.",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 12) {
                EngineCard(
                    accent: accent,
                    selected: state.engine == .ane,
                    icon: "sparkles",
                    name: "WhisperKit · ANE",
                    tag: "EMPFOHLEN",
                    desc: "Läuft auf der Apple Neural Engine. Audio verlässt deinen Mac nicht.",
                    stats: [("GESCHWINDIGKEIT", "4.2× Echtzeit"),
                            ("PRIVATSPHÄRE",   "On-device"),
                            ("SPRACHEN",       "99")]
                ) { state.engine = .ane }

                EngineCard(
                    accent: accent,
                    selected: state.engine == .cloud,
                    icon: "flame",
                    name: "Whisper · Cloud",
                    tag: nil,
                    desc: "Höhere Genauigkeit bei Akzenten und Fachsprache. Audio wird verschlüsselt übertragen.",
                    stats: [("GESCHWINDIGKEIT", "1.8× Echtzeit"),
                            ("PRIVATSPHÄRE",   "TLS · 24h"),
                            ("SPRACHEN",       "57")]
                ) { state.engine = .cloud }

                OnboardingToggleRow(
                    symbol: "flame",
                    title: "Claude analysieren lassen",
                    subtitle: "TL;DR, Aktionspunkte, Highlights & Kapitel werden mit Claude Haiku 4.5 destilliert.",
                    badge: "ANALYSE",
                    value: $state.claudeAnalysisEnabled,
                    accent: accent
                )
                .padding(.top, 4)
            }
            .frame(maxWidth: 460)
        }
    }
}

struct EngineCard: View {
    let accent: Color
    let selected: Bool
    let icon: String
    let name: String
    let tag: String?
    let desc: String
    let stats: [(String, String)]
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(selected ? accent.opacity(0.18) : Color.white.opacity(0.04))
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(selected ? accent.opacity(0.4) : Neon.strokeHairline, lineWidth: 0.5)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(selected ? accent : Neon.textSecondary)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(name)
                                .font(.neonDisplay(18))
                                .foregroundStyle(Neon.textPrimary)
                            if let tag {
                                Text(tag)
                                    .font(.neonMono(9, weight: .semibold))
                                    .tracking(1.0)
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(accent.opacity(0.12))
                                    )
                            }
                        }
                        Text(desc)
                            .font(.neonBody(13))
                            .foregroundStyle(Neon.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    radioDot
                }
                Divider().background(Neon.strokeHairline)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(stats, id: \.0) { stat in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stat.0)
                                .font(.neonMono(9))
                                .tracking(0.6)
                                .foregroundStyle(Neon.textTertiary.opacity(0.6))
                            Text(stat.1)
                                .font(.neonMono(11))
                                .foregroundStyle(selected ? Neon.textPrimary : Neon.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? accent.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? accent.opacity(0.45) : Neon.strokeHairline, lineWidth: selected ? 1 : Neon.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var radioDot: some View {
        ZStack {
            Circle()
                .fill(selected ? accent : .clear)
            Circle()
                .stroke(selected ? accent : Neon.strokeDefault, lineWidth: 1.5)
            if selected {
                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 18, height: 18)
    }
}

struct EngineVisual: View {
    @ObservedObject var state: OnboardingState
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            Text("VERARBEITUNGS-PIPELINE")
                .font(.neonMono(10))
                .tracking(1.0)
                .foregroundStyle(Neon.textTertiary)
                .padding(.bottom, 12)

            PipeNode(icon: "mic", label: "Mikrofon", sub: "Eingabe · 48 kHz",
                     active: true, highlight: false, accent: accent)
            PipeArrow(accent: accent, dashed: false)
            PipeNode(icon: state.engine == .ane ? "sparkles" : "flame",
                     label: state.engine == .ane ? "WhisperKit · ANE" : "Whisper · Cloud",
                     sub: state.engine == .ane ? "Lokal · M-Series Neural Engine" : "Verschlüsselt · TLS 1.3",
                     active: true, highlight: true, accent: accent)
            PipeArrow(accent: accent, dashed: !state.claudeAnalysisEnabled)
            PipeNode(icon: "flame",
                     label: "Claude · Analyse",
                     sub: state.claudeAnalysisEnabled ? "Haiku 4.5 · TL;DR, Tasks, Kapitel" : "Deaktiviert — nur Roh-Transkript",
                     active: state.claudeAnalysisEnabled, highlight: false, accent: accent)
            PipeArrow(accent: accent, dashed: false)
            PipeNode(icon: "tray.full", label: "NeoQuill · Mediathek",
                     sub: "Lokal verschlüsselt · ~/Library/Quill",
                     active: true, highlight: false, accent: accent)
        }
        .frame(width: 380)
    }
}

struct PipeNode: View {
    let icon: String
    let label: String
    let sub: String
    let active: Bool
    let highlight: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(highlight ? accent.opacity(0.18) : Color.white.opacity(0.04))
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(highlight ? accent : Neon.textSecondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.neonBody(13, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                Text(sub)
                    .font(.neonMono(10))
                    .tracking(0.4)
                    .foregroundStyle(Neon.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(highlight ? accent.opacity(0.08) : Color(hex: 0x242422).opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(highlight ? accent.opacity(0.4) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .opacity(active ? 1 : 0.45)
    }
}

struct PipeArrow: View {
    let accent: Color
    let dashed: Bool

    var body: some View {
        ZStack {
            if dashed {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(accent.opacity(0.35))
                            .frame(width: 1, height: 3)
                    }
                }
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [accent.opacity(0.4), accent.opacity(0.12)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 1, height: 14)
            }
        }
        .frame(height: 16)
    }
}
