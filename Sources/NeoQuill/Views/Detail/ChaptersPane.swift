import SwiftUI

// Kapitel-Liste: timestamp · index-pill · label · duration · play-glyph.

struct ChaptersPane: View {

    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(meeting.chapters.enumerated()), id: \.element.id) { idx, c in
                ChapterRow(chapter: c, index: idx + 1, accent: accent)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct ChapterRow: View {
    let chapter: Chapter
    let index: Int
    let accent: Color

    var body: some View {
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
            GlyphView(name: .play, size: 11, color: Neon.textTertiary)
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
    }
}
