import SwiftUI

// Live-Aufnahme-View, gespeist vom RecordingController:
// elapsed kommt vom Controller, liveLines vom WhisperKit-Stream.

struct RecordingView: View {

    @ObservedObject var recorder: RecordingController
    var accent: Color = Neon.brandPrimary
    var onStop: () -> Void = {}

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                DetailToolbar(title: "Live-Aufnahme", showLayoutSwitch: false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        hero
                        LiveWaveform()
                        liveTranscript
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 36)
                    .padding(.bottom, 140)
                }
            }

            FloatingPill(elapsed: Int(recorder.elapsed), onStop: onStop)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            LiveOrb()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Neon.recordingDot).frame(width: 5, height: 5)
                    Text(eyebrowLabel)
                        .font(.neonMono(10, weight: .semibold))
                        .tracking(1.0)
                        .foregroundStyle(Neon.recordingDotBright)
                }
                Text(AudioPlayer.formatted(seconds: Int(recorder.elapsed)))
                    .font(.neonMonoTimer)
                    .foregroundStyle(Neon.textPrimary)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 8) {
                ChipButton(icon: .sparkles, label: recorder.modelLabel, tone: .brand)
                ChipButton(icon: .mic,      label: recorder.device, tone: .info)
            }
        }
    }

    private var eyebrowLabel: String {
        switch recorder.state {
        case .preparing:   return "STARTET …"
        case .recording:   return "LIVE · WIRD AUFGENOMMEN"
        case .processing:  return "VERARBEITEN …"
        case .error(let m): return "FEHLER · \(m.prefix(60))"
        case .idle:        return "BEREIT"
        }
    }

    private var liveTranscript: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("WIRD TRANSKRIBIERT…").neonEyebrow()
            VStack(alignment: .leading, spacing: 18) {
                if recorder.liveLines.isEmpty {
                    PendingRow(accent: accent)
                } else {
                    ForEach(Array(recorder.liveLines.enumerated()), id: \.element.id) { idx, line in
                        LiveTranscriptRow(
                            line: line,
                            isLast: idx == recorder.liveLines.count - 1,
                            accent: accent
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                listeningPill
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var listeningPill: some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text("Hört zu …")
                .font(.neonMono(11))
                .foregroundStyle(Neon.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.03)))
        .overlay(Capsule().stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth))
    }
}

private struct PendingRow: View {
    let accent: Color
    var body: some View {
        HStack(spacing: 14) {
            Text("00:00").font(.neonMono(10)).foregroundStyle(Neon.textTertiary).frame(width: 44, alignment: .trailing)
            Avatar(initials: "NK", color: Neon.brandPrimary, size: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text("Du").font(.neonBody(13, weight: .medium)).foregroundStyle(Neon.textPrimary)
                Text("Sprich los — sobald WhisperKit läuft, erscheint hier dein Transkript.")
                    .font(.neonBody(14))
                    .foregroundStyle(Neon.textTertiary)
                    .italic()
            }
        }
    }
}

private struct LiveTranscriptRow: View {

    let line: TranscriptLine
    let isLast: Bool
    let accent: Color

    @State private var blink = false
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var speakerColor: Color {
        switch line.who {
        case "NK": return Neon.brandPrimary
        case "SE": return Neon.Speaker.indigo
        case "TM": return Neon.Speaker.amber
        default:   return Neon.Speaker.blue
        }
    }

    private var speakerName: String {
        switch line.who {
        case "NK": return "Du"
        case "SE": return "Sarah Ebner"
        case "TM": return "Thomas Müller"
        default:   return line.who
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(line.timestamp)
                .font(.neonMono(10))
                .foregroundStyle(Neon.textTertiary)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 2)

            Avatar(initials: line.who, color: speakerColor, size: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(speakerName)
                    .font(.neonBody(13, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line.body)
                        .font(.neonBody(14))
                        .lineSpacing(2)
                        .foregroundStyle(Neon.textSecondary)
                    if isLast {
                        Text("▍")
                            .foregroundStyle(accent)
                            .opacity(blink ? 1 : 0)
                            .onReceive(timer) { _ in blink.toggle() }
                    }
                }
            }
        }
    }
}
