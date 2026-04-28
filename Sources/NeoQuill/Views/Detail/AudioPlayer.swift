import SwiftUI

// Sticky 64h Player: Play/Pause | Time | Waveform (120 bars) | Total | Rewind/Forward | Speed.

struct AudioPlayer: View {

    var totalSeconds: Int = 32 * 60 + 14
    var accent: Color = Neon.brandPrimary

    @State private var playing = false
    @State private var position: Int = 127
    @State private var timer: Timer?

    private var bars: [Double] {
        (0..<120).map { i in
            let seed = sin(Double(i) * 0.7) * 0.5
                + sin(Double(i) * 0.13) * 0.4
                + cos(Double(i) * 0.31) * 0.3
            return 0.18 + abs(seed) * 0.7
        }
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(position) / Double(totalSeconds)
    }

    var body: some View {
        HStack(spacing: 14) {
            playPauseButton
            timeLabel(Self.formatted(seconds: position), tertiary: false)
            waveform
            timeLabel(Self.formatted(seconds: totalSeconds), tertiary: true)
            ToolbarButton(icon: .rewind)
            ToolbarButton(icon: .forward)
            speedPill
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .top) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
        .onDisappear { timer?.invalidate() }
    }

    private var playPauseButton: some View {
        Button {
            playing.toggle()
            timer?.invalidate()
            if playing {
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    position = min(totalSeconds, position + 1)
                    if position == totalSeconds { playing = false; timer?.invalidate() }
                }
            }
        } label: {
            ZStack {
                Circle().fill(accent)
                GlyphView(name: playing ? .pause : .play, size: 14, color: .white)
            }
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(accent.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func timeLabel(_ text: String, tertiary: Bool) -> some View {
        Text(text)
            .font(.neonMono(11))
            .foregroundStyle(tertiary ? Neon.textTertiary : Neon.textSecondary)
            .frame(width: 44, alignment: tertiary ? .trailing : .leading)
            .monospacedDigit()
    }

    private var waveform: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, h in
                    let isPast = (Double(i) / Double(bars.count)) < progress
                    Capsule()
                        .fill(isPast ? accent : Color.white.opacity(0.16))
                        .frame(height: max(2, geo.size.height * h))
                        .frame(maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { value in
                let pct = max(0, min(1, value.x / geo.size.width))
                position = Int(Double(totalSeconds) * pct)
            }
        }
        .frame(height: 36)
    }

    private var speedPill: some View {
        Text("1.0×")
            .font(.neonMono(10))
            .foregroundStyle(Neon.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
    }

    static func formatted(seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let s = max(0, seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
