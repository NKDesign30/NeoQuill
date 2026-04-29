import SwiftUI

// SwiftUI-Inhalt der Floating-Pill. Drei Visual-Modi:
// - .detected(app:) → "<App> Call · Aufnehmen?" + ✓ ✗
// - .preparing      → "Vorbereiten…" Spinner
// - .recording      → roter Punkt + Timer + Stop
// - .processing     → "Wird transkribiert…" Spinner

struct MeetingPill: View {

    @ObservedObject var state: MeetingPillState

    var body: some View {
        Group {
            switch state.mode {
            case .detected(let app): detectedPill(app: app)
            case .preparing:         simplePill(text: "Vorbereiten…", showSpinner: true)
            case .recording:         recordingPill
            case .processing:        simplePill(text: "Wird transkribiert…", showSpinner: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    // MARK: - Detected

    private func detectedPill(app: CallApp) -> some View {
        HStack(spacing: 12) {
            Image(systemName: appIcon(app))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Neon.brandPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.rawValue) · Aufnehmen?")
                    .font(.neonBody(13, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                Text("NeoQuill hat ein Meeting erkannt")
                    .font(.neonBody(11))
                    .foregroundStyle(Neon.textTertiary)
            }

            Spacer(minLength: 8)

            Button(action: state.onDismiss) {
                Text("Ablehnen")
                    .font(.neonBody(12, weight: .medium))
                    .foregroundStyle(Neon.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)

            Button(action: state.onAccept) {
                Text("Aufnehmen")
                    .font(.neonBody(12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Neon.brandPrimary))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recording

    @State private var breathe = false

    private var recordingPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Neon.recordingDot)
                .frame(width: 8, height: 8)
                .opacity(breathe ? 0.45 : 1.0)
                .scaleEffect(breathe ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: breathe)

            Text(formatElapsed(state.elapsedSeconds))
                .font(.neonMono(12, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
                .monospacedDigit()

            Text("Aufnahme")
                .font(.neonBody(12))
                .foregroundStyle(Neon.textTertiary)

            Spacer(minLength: 8)

            Button(action: state.onStop) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
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
        .onAppear { breathe = true }
    }

    // MARK: - Simple

    private func simplePill(text: String, showSpinner: Bool) -> some View {
        HStack(spacing: 10) {
            if showSpinner {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
            Text(text)
                .font(.neonBody(12, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
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
