import SwiftUI

// Search-Bar oben, dann Transkript-Zeilen mit Highlight-Marker.

struct TranscriptPane: View {

    let meeting: MeetingDetail
    @Binding var query: String
    var accent: Color = Neon.brandPrimary

    @State private var visibleCount = TranscriptPaging.pageSize
    @State private var pagedMeetingId: String?
    @State private var pagedQuery = ""
    @State private var showsRawTranscript = false

    var body: some View {
        let displayRows = TranscriptPresentation.rows(
            from: meeting.transcript,
            mode: showsRawTranscript ? .raw : .collapsedRepeatedRuns
        )
        let filtered = TranscriptPresentation.filteredRows(displayRows, query: query)
        let requestedVisibleCount = isPagingCurrent ? visibleCount : TranscriptPaging.pageSize
        let clampedVisibleCount = TranscriptPaging.visibleCount(total: filtered.count, requested: requestedVisibleCount)
        let visibleRows = Array(filtered.prefix(clampedVisibleCount))

        VStack(alignment: .leading, spacing: 20) {
            searchBar(
                filteredCount: filtered.count,
                loadedCount: clampedVisibleCount,
                totalCount: meeting.transcript.count,
                isRaw: showsRawTranscript
            )
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(visibleRows) { row in
                    switch row.kind {
                    case .line(let line):
                        TranscriptRow(line: line, meeting: meeting, accent: accent, query: query)
                    case .collapsedRun(let firstLine, let hiddenCount):
                        TranscriptCollapsedRunRow(line: firstLine, hiddenCount: hiddenCount, accent: accent)
                    }
                }
                TranscriptLoadMoreFooter(
                    visibleCount: clampedVisibleCount,
                    totalCount: filtered.count,
                    accent: accent,
                    loadMore: {
                        pagedMeetingId = meeting.id
                        pagedQuery = query
                        visibleCount = TranscriptPaging.nextCount(current: clampedVisibleCount, total: filtered.count)
                    }
                )
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .onAppear(perform: resetPaging)
        .onChange(of: meeting.id) { _, _ in resetPaging() }
        .onChange(of: query) { _, _ in resetPaging() }
        .onChange(of: showsRawTranscript) { _, _ in resetPaging() }
    }

    private var isPagingCurrent: Bool {
        pagedMeetingId == meeting.id && pagedQuery == query
    }

    private func searchBar(
        filteredCount: Int,
        loadedCount: Int,
        totalCount: Int,
        isRaw: Bool
    ) -> some View {
        HStack(spacing: 10) {
            GlyphView(name: .search, size: 13, color: Neon.textTertiary)
            TextField("Im Transkript suchen…", text: $query)
                .textFieldStyle(.plain)
                .font(.neonBody(13))
                .foregroundStyle(Neon.textPrimary)
            Spacer()
            Text(countLabel(
                filteredCount: filteredCount,
                loadedCount: loadedCount,
                totalCount: totalCount,
                isRaw: isRaw
            ))
                .font(.neonMono(10))
                .foregroundStyle(Neon.textTertiary)
            Button {
                showsRawTranscript.toggle()
            } label: {
                Text(isRaw ? "Roh" : "Clean")
                    .font(.neonMono(10))
                    .foregroundStyle(isRaw ? Neon.statusWarning : accent)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill((isRaw ? Neon.statusWarning : accent).opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help(isRaw ? "Rohtranskript anzeigen" : "Bereinigtes Transkript anzeigen")
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

    private func resetPaging() {
        pagedMeetingId = meeting.id
        pagedQuery = query
        visibleCount = TranscriptPaging.pageSize
    }

    private func countLabel(
        filteredCount: Int,
        loadedCount: Int,
        totalCount: Int,
        isRaw: Bool
    ) -> String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isRaw {
                return "\(loadedCount) geladen · \(totalCount) roh"
            }
            return "\(loadedCount) Blöcke · \(totalCount) roh repräsentiert"
        }
        if isRaw {
            return "\(loadedCount) geladen · \(filteredCount) Treffer · \(totalCount) roh"
        }
        return "\(loadedCount) Blöcke · \(filteredCount) Treffer · \(totalCount) roh"
    }
}

private struct TranscriptCollapsedRunRow: View {
    let line: TranscriptLine
    let hiddenCount: Int
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(line.timestamp)
                .font(.neonMono(11))
                .foregroundStyle(Neon.textTertiary)
                .frame(width: 42, alignment: .trailing)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    GlyphView(name: .chevDown, size: 11, color: accent)
                    Text("\(hiddenCount.formatted()) Wiederholungen kollabiert")
                        .font(.neonMono(10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(line.body)
                        .font(.neonBody(12))
                        .foregroundStyle(Neon.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: Neon.hairlineWidth)
                )
            }
        }
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
                    SpeakerSourceBadge(source: line.speakerSource, confidence: line.confidence)
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
