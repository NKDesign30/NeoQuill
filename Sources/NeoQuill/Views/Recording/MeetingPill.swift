import SwiftUI

// Floating-Pill mit vier Visual-Modi:
// - .detected(app:) → Frage mit Akzeptieren/Ablehnen-Buttons + App-Icon
// - .preparing      → "Vorbereiten…" mit Spinner
// - .recording      → REC-Eyebrow + Timer + Live-Audio-Bars + Stop
// - .processing     → "Wird transkribiert…" mit Spinner
//
// Design: warm-dark Capsule mit ultraThinMaterial, 0.5pt Hairline-Stroke,
// Brand-Emerald als Akzent fuer Detected, recordingDot fuer aktive Aufnahme.

struct MeetingPill: View {

    @ObservedObject var state: MeetingPillState

    var body: some View {
        Group {
            switch state.mode {
            case .detected(let app): detectedPill(app: app)
            case .preparing:         simplePill(text: "Vorbereiten", accent: Neon.brandPrimary)
            case .recording:         recordingPill
            case .processing:        simplePill(text: "Wird transkribiert", accent: Neon.brandPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(pillBackground)
        .overlay(
            Capsule().stroke(borderColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 28, x: 0, y: 14)
        .padding(10)
    }

    // MARK: - Background / Border tokenisiert pro Modus

    private var pillBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
    }

    private var gradientColors: [Color] {
        switch state.mode {
        case .recording:
            return [Neon.recordingDot.opacity(0.10), .clear]
        case .detected:
            return [Neon.brandPrimary.opacity(0.08), .clear]
        default:
            return [Color.white.opacity(0.02), .clear]
        }
    }

    private var borderColor: Color {
        switch state.mode {
        case .recording: return Neon.recordingDot.opacity(0.25)
        case .detected:  return Neon.brandPrimary.opacity(0.30)
        default:         return Color.white.opacity(0.14)
        }
    }

    // MARK: - Detected

    private func detectedPill(app: CallApp) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Neon.brandPrimary.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: appIcon(app))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Neon.brandPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MEETING ERKANNT")
                    .font(.neonMono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Neon.brandPrimary)
                Text(app.rawValue)
                    .font(.neonBody(13, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
            }

            Spacer(minLength: 12)

            Button(action: state.onDismiss) {
                Text("Ignorieren")
                    .font(.neonBody(12, weight: .medium))
                    .foregroundStyle(Neon.textSecondary)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(
                        Capsule().fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            Button(action: state.onAccept) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Aufnehmen")
                        .font(.neonBody(12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Neon.brandPrimary, Neon.brandPrimary.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .shadow(color: Neon.brandPrimary.opacity(0.4), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recording

    @State private var pulse = false

    private var recordingPill: some View {
        HStack(spacing: 12) {
            recordingDot

            VStack(alignment: .leading, spacing: 1) {
                Text("REC")
                    .font(.neonMono(9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(Neon.recordingDot)
                Text(formatElapsed(state.elapsedSeconds))
                    .font(.neonMono(13, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                    .monospacedDigit()
            }

            Divider()
                .frame(height: 22)
                .overlay(Color.white.opacity(0.12))

            audioLevelBars

            Spacer(minLength: 8)

            Button(action: state.onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Stoppen")
                        .font(.neonBody(12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Neon.recordingDot, Neon.recordingDot.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .shadow(color: Neon.recordingDot.opacity(0.45), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
        }
        .onAppear { pulse = true }
    }

    private var recordingDot: some View {
        ZStack {
            // Outer Halo — pulst
            Circle()
                .fill(Neon.recordingDot.opacity(0.30))
                .frame(width: 22, height: 22)
                .scaleEffect(pulse ? 1.3 : 0.85)
                .opacity(pulse ? 0.0 : 0.7)
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            // Solid Dot
            Circle()
                .fill(Neon.recordingDot)
                .frame(width: 9, height: 9)
                .shadow(color: Neon.recordingDot.opacity(0.7), radius: 4)
        }
        .frame(width: 22, height: 22)
    }

    private var audioLevelBars: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<5, id: \.self) { idx in
                AudioBar(
                    level: clampedLevel,
                    index: idx,
                    isActive: state.mode == .recording
                )
            }
        }
        .frame(height: 22)
    }

    private var clampedLevel: Float {
        // Mic-RMS ist meist < 0.05 — auf Anzeige-Bereich strecken (bis ~0.2 → full).
        let scaled = min(max(state.audioLevel * 5, 0), 1)
        return scaled
    }

    // MARK: - Simple (preparing / processing)

    private func simplePill(text: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .tint(accent)
            Text(text)
                .font(.neonBody(12, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(accent.opacity(0.5))
                        .frame(width: 3, height: 3)
                }
            }
        }
    }

    // MARK: - Helpers

    private func appIcon(_ app: CallApp) -> String {
        switch app {
        case .teams:    return "person.2.wave.2.fill"
        case .zoom:     return "video.fill"
        case .facetime: return "video.fill"
        case .slack:    return "bubble.left.and.bubble.right.fill"
        case .webex:    return "video.fill"
        case .discord:  return "gamecontroller.fill"
        case .browser:  return "globe"
        case .unknown:  return "phone.fill"
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Audio Bar

private struct AudioBar: View {
    let level: Float
    let index: Int
    let isActive: Bool

    @State private var animatedHeight: CGFloat = 4

    private var targetHeight: CGFloat {
        guard isActive else { return 4 }
        // Per-Bar variance damit es nach echtem Equalizer aussieht statt Gleichschritt.
        let variance: [Float] = [0.55, 0.85, 1.0, 0.75, 0.50]
        let scaled = CGFloat(level * variance[index % variance.count])
        return 4 + scaled * 16
    }

    private var color: Color {
        let t = CGFloat(level)
        return Color(
            red: 1.0,
            green: 0.55 - 0.15 * t,
            blue: 0.45 - 0.10 * t
        )
    }

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 3, height: animatedHeight)
            .animation(.easeOut(duration: 0.12), value: animatedHeight)
            .onChange(of: level) { _, _ in
                animatedHeight = targetHeight
            }
            .onAppear {
                animatedHeight = targetHeight
            }
    }
}
