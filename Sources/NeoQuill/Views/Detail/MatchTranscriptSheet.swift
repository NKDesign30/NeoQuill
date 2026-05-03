import SwiftUI

struct MatchTranscriptSheet: View {
    let fileURL: URL
    let hint: TranscriptDownloadWatcher.Hint
    let detectedAt: Date
    let candidateMeetingIds: [String]

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMeetingId: String?
    @State private var showAllMeetings = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            if showAllMeetings {
                meetingList(state.meetings)
            } else if candidateMeetingIds.isEmpty {
                emptyMatches
            } else {
                meetingList(candidateMatches)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Ignorieren", role: .destructive) {
                    TranscriptDownloadWatcher.markProcessed(fileURL)
                    dismiss()
                }

                Spacer()

                Button(showAllMeetings ? "Nur Treffer zeigen" : "Anderes Meeting wählen") {
                    showAllMeetings.toggle()
                }

                Button("Anwenden") { applyImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedMeetingId == nil)
            }
        }
        .padding(24)
        .frame(width: 540, height: 480)
        .preferredColorScheme(.dark)
        .background(Neon.windowBackdrop)
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transkript erkannt")
                .font(.neonDisplay(20))
                .foregroundStyle(Neon.textPrimary)
            HStack(spacing: 8) {
                GlyphView(name: .download, size: 12, color: Neon.brandPrimary)
                Text(fileURL.lastPathComponent)
                    .font(.neonMono(12))
                    .foregroundStyle(Neon.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 12) {
                Text(formatLabel(for: hint))
                    .font(.neonBody(11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Neon.brandPrimary.opacity(0.12)))
                    .foregroundStyle(Neon.brandPrimary)
                Text("Erkannt: \(detectedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.neonBody(11))
                    .foregroundStyle(Neon.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var emptyMatches: some View {
        VStack(spacing: 8) {
            Text("Kein Meeting im 2-Stunden-Fenster gefunden.")
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
            Text("Wähle ein anderes Meeting aus der vollständigen Liste.")
                .font(.neonBody(11))
                .foregroundStyle(Neon.textTertiary)
            Button("Alle Meetings zeigen") { showAllMeetings = true }
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private func meetingList(_ summaries: [MeetingSummary]) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(summaries) { summary in
                    MeetingChoiceRow(
                        summary: summary,
                        selected: selectedMeetingId == summary.id,
                        onSelect: { selectedMeetingId = summary.id }
                    )
                }
            }
        }
    }

    private var candidateMatches: [MeetingSummary] {
        let order = Dictionary(uniqueKeysWithValues: candidateMeetingIds.enumerated().map { ($0.element, $0.offset) })
        return state.meetings
            .filter { candidateMeetingIds.contains($0.id) }
            .sorted { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    }

    private func applyImport() {
        guard let meetingId = selectedMeetingId else { return }
        do {
            _ = try state.importPlatformTranscript(meetingId: meetingId, fileURL: fileURL)
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func formatLabel(for hint: TranscriptDownloadWatcher.Hint) -> String {
        switch hint {
        case .teamsVTT:      return "Microsoft Teams · VTT"
        case .teamsMetadata: return "Microsoft Teams · Metadata"
        case .meetEntries:   return "Google Meet · Entries"
        case .zoomVTT:       return "Zoom · VTT"
        case .zoomTimeline:  return "Zoom · Timeline"
        case .generic:       return "Generisches VTT"
        }
    }
}

private struct MeetingChoiceRow: View {
    let summary: MeetingSummary
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.neonBody(13, weight: .medium))
                        .foregroundStyle(Neon.textPrimary)
                        .lineLimit(1)
                    Text("\(summary.date) · \(summary.time) · \(summary.duration)")
                        .font(.neonBody(11))
                        .foregroundStyle(Neon.textTertiary)
                }
                Spacer()
                Text(summary.platform.rawValue)
                    .font(.neonMono(10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(summary.platform.accent.opacity(0.16)))
                    .foregroundStyle(summary.platform.accent)
                if selected {
                    GlyphView(name: .checkCircle, size: 14, color: Neon.brandPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Neon.brandPrimary.opacity(0.12) : Color.white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
}
