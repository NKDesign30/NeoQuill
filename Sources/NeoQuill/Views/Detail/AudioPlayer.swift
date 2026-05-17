import AVFoundation
import SwiftUI

// Sticky 64h Player: Play/Pause | Time | Waveform (120 bars) | Total | Rewind/Forward | Speed.

struct AudioPlayer: View {

    var totalSeconds: Int = 0
    var audioURL: String?
    var accent: Color = Neon.brandPrimary
    var waveformSeed: Int = 0    // Hash des Meeting-IDs → andere Aufnahme = anderes Pattern
    @ObservedObject var playback: AudioPlaybackController

    @State private var playing = false
    @State private var position: TimeInterval = 0
    @State private var timer: Timer?
    @State private var player: AVAudioPlayer?
    @State private var loadFailed = false
    @State private var playbackRate: Float = 1
    @State private var playbackRateCorrected = false

    private var bars: [Double] {
        let seed = Double(waveformSeed)
        return (0..<120).map { i in
            let v = sin(Double(i) * 0.7 + seed * 0.01) * 0.5
                + sin(Double(i) * 0.13 + seed * 0.03) * 0.4
                + cos(Double(i) * 0.31 + seed * 0.07) * 0.3
            return 0.18 + abs(v) * 0.7
        }
    }

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1.0, Double(position) / Double(totalSeconds))
    }

    private var safeTotal: Int { max(totalSeconds, 1) }

    var body: some View {
        HStack(spacing: 14) {
            playPauseButton
            timeLabel(Self.formatted(seconds: Int(position)), tertiary: false)
            waveform
            timeLabel(Self.formatted(seconds: safeTotal), tertiary: true)
            ToolbarButton(icon: .rewind) { seek(by: -10) }
            ToolbarButton(icon: .forward) { seek(by: 10) }
            speedPill
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .top) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
        .onDisappear { stopTimer(); player?.pause() }
        .onChange(of: audioURL) { _, _ in resetPlayback() }
        .onChange(of: playback.seekTo) { _, target in
            guard let target else { return }
            handleExternalSeek(to: target)
            playback.clearSeek()
        }
    }

    /// Externer Seek von z.B. ChaptersPane: springt zur Sekunde und startet
    /// die Wiedergabe (User-Erwartung beim Klick auf Kapitel).
    private func handleExternalSeek(to seconds: TimeInterval) {
        guard canPlay else { return }
        if player == nil { loadPlayer() }
        seek(to: seconds)
        if player?.isPlaying == false {
            player?.play()
            playing = true
            startTimer()
        }
    }

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            ZStack {
                Circle().fill(canPlay ? accent : Neon.textQuaternary)
                GlyphView(name: playing ? .pause : .play, size: 14, color: .white)
            }
            .frame(width: 36, height: 36)
            .overlay(Circle().stroke(accent.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!canPlay)
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
                seek(to: TimeInterval(safeTotal) * pct)
            }
        }
        .frame(height: 36)
    }

    private var speedPill: some View {
        let prefix = playbackRateCorrected ? "Auto " : ""
        return Text("\(prefix)\(Self.formatted(rate: playbackRate))×")
            .font(.neonMono(10))
            .foregroundStyle(Neon.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
    }

    private var canPlay: Bool {
        guard let audioURL, !audioURL.isEmpty else { return false }
        return !loadFailed
    }

    private func togglePlayback() {
        guard canPlay else { return }
        if player == nil {
            loadPlayer()
        }
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            playing = false
            stopTimer()
        } else {
            player.play()
            playing = true
            startTimer()
        }
    }

    private func loadPlayer() {
        guard let audioURL else { return }
        let url = URL(fileURLWithPath: audioURL)
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.enableRate = true
            let correction = AudioPlaybackPitchGuard.decide(
                fileDuration: p.duration,
                expectedDuration: TimeInterval(totalSeconds)
            )
            p.rate = correction.rate
            player = p
            playbackRate = correction.rate
            playbackRateCorrected = correction.corrected
            if correction.corrected {
                NSLog(
                    "[AudioPlayer] playback rate corrected to \(correction.rate) for \(audioURL) (\(correction.reason ?? "duration mismatch"))"
                )
            }
            loadFailed = false
        } catch {
            NSLog("[AudioPlayer] failed to load \(audioURL): \(error)")
            loadFailed = true
            playing = false
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let player else { return }
            position = player.currentTime
            if !player.isPlaying {
                playing = false
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func seek(by delta: TimeInterval) {
        seek(to: position + delta)
    }

    private func seek(to target: TimeInterval) {
        if player == nil {
            loadPlayer()
        }
        let clamped = max(0, min(TimeInterval(safeTotal), target))
        position = clamped
        player?.currentTime = clamped
    }

    private func resetPlayback() {
        stopTimer()
        player?.stop()
        player = nil
        playing = false
        position = 0
        loadFailed = false
        playbackRate = 1
        playbackRateCorrected = false
    }

    static func formatted(seconds: Int) -> String {
        let m = max(0, seconds) / 60
        let s = max(0, seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private static func formatted(rate: Float) -> String {
        String(format: "%.1f", Double(rate))
    }
}
