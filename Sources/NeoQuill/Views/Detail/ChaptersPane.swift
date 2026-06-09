import SwiftUI

// Kapitel-Liste: timestamp · index-pill · label · duration · play-button.
// Klick auf einen Chapter-Row springt im AudioPlayer zur Stelle und spielt ab.

struct ChaptersPane: View {

    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary
    @ObservedObject var playback: AudioPlaybackController

    var body: some View {
        Group {
            if meeting.chapters.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(meeting.chapters.enumerated()), id: \.element.id) { idx, c in
                        ChapterRow(
                            chapter: c,
                            index: idx + 1,
                            accent: accent,
                            onTap: { jumpTo(chapter: c) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("KEINE KAPITEL")
                .font(.neonMono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Neon.textTertiary)
            Text(meeting.processing
                 ? "Themen-Cluster werden noch erkannt — kommt gleich."
                 : "Diese Aufnahme war zu kurz oder ohne erkennbare Themen-Wechsel.")
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }

    private func jumpTo(chapter: Chapter) {
        guard let seconds = TranscriptTimecode.parse(chapter.timestamp) else { return }
        playback.seekTo = seconds
    }
}

private struct ChapterRow: View {
    let chapter: Chapter
    let index: Int
    let accent: Color
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Text(chapter.timestamp)
                    .font(.neonMono(11))
                    .foregroundStyle(Neon.textTertiary)
                    .frame(width: 44, alignment: .leading)
                    .monospacedDigit()

                Text(String(format: "%02d", index))
                    .font(.neonMono(10, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent.opacity(0.10)))

                Text(chapter.label)
                    .font(.neonBody(14))
                    .foregroundStyle(Neon.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(chapter.duration)
                    .font(.neonMono(10))
                    .foregroundStyle(Neon.textTertiary)
                GlyphView(name: .play, size: 11, color: accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
