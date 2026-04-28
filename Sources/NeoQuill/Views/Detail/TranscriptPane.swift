import SwiftUI

// Search-Bar oben, dann Transkript-Zeilen mit Highlight-Marker.

struct TranscriptPane: View {

    let meeting: MeetingDetail
    @Binding var query: String
    var accent: Color = Neon.brandPrimary

    private var filtered: [TranscriptLine] {
        guard !query.isEmpty else { return meeting.transcript }
        let q = query.lowercased()
        return meeting.transcript.filter { $0.body.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            searchBar
            VStack(alignment: .leading, spacing: 18) {
                ForEach(filtered) { line in
                    TranscriptRow(line: line, meeting: meeting, accent: accent, query: query)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            GlyphView(name: .search, size: 13, color: Neon.textTertiary)
            TextField("Im Transkript suchen…", text: $query)
                .textFieldStyle(.plain)
                .font(.neonBody(13))
                .foregroundStyle(Neon.textPrimary)
            Spacer()
            Text("\(filtered.count) / \(meeting.transcript.count)")
                .font(.neonMono(10))
                .foregroundStyle(Neon.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }
}

private struct TranscriptRow: View {
    let line: TranscriptLine
    let meeting: MeetingDetail
    let accent: Color
    let query: String

    private var participant: Participant? {
        meeting.participants.first(where: { $0.id == line.who })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(line.timestamp)
                .font(.neonMono(10))
                .foregroundStyle(Neon.textTertiary)
                .frame(width: 56, alignment: .trailing)
                .padding(.top, 2)

            if let p = participant {
                Avatar(initials: p.id, color: p.color, size: 28)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(participant?.name ?? line.who)
                        .font(.neonBody(13, weight: .medium))
                        .foregroundStyle(Neon.textPrimary)
                    if line.highlight {
                        Text("● ENTSCHEIDUNG")
                            .font(.neonMono(9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                    }
                }
                bodyText
            }
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        if line.highlight {
            Text(highlighted(line.body, query: query, accent: accent))
                .font(.neonBody(14))
                .lineSpacing(2)
                .padding(.leading, 12)
                .padding(.vertical, 0)
                .overlay(alignment: .leading) {
                    Rectangle().fill(accent).frame(width: 2)
                }
                .foregroundStyle(Neon.textPrimary)
        } else {
            Text(highlighted(line.body, query: query, accent: accent))
                .font(.neonBody(14))
                .lineSpacing(2)
                .foregroundStyle(Neon.textSecondary)
        }
    }

    private func highlighted(_ text: String, query: String, accent: Color) -> AttributedString {
        var attr = AttributedString(text)
        guard !query.isEmpty,
              let range = attr.range(of: query, options: .caseInsensitive)
        else { return attr }
        attr[range].backgroundColor = accent.opacity(0.25)
        attr[range].foregroundColor = Neon.textPrimary
        return attr
    }
}
