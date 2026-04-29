import SwiftUI

// Variant A: Single-Column Editorial. HeaderHero → Tabs → SummaryPane/Transcript/Chapters → AudioPlayer.

enum DetailTab: String, CaseIterable, Identifiable {
    case summary    = "Zusammenfassung"
    case transcript = "Transkript"
    case chapters   = "Kapitel"

    var id: String { rawValue }
}

struct DetailEditorial: View {

    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary

    @State private var tab: DetailTab = .summary
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: meeting.title, meeting: meeting)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeaderHero(meeting: meeting, accent: accent)
                    tabsBar
                    Group {
                        switch tab {
                        case .summary:    SummaryPane(meeting: meeting, accent: accent)
                        case .transcript: TranscriptPane(meeting: meeting, query: $state.query, accent: accent)
                        case .chapters:   ChaptersPane(meeting: meeting, accent: accent)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 28)
                    .padding(.bottom, 48)
                }
            }

            AudioPlayer(
                totalSeconds: parseDuration(meeting.duration),
                accent: accent,
                waveformSeed: abs(meeting.id.hashValue) % 9999
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabsBar: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases) { item in
                TabButton(
                    label: item.rawValue,
                    count: count(for: item),
                    active: tab == item,
                    accent: accent,
                    onTap: { tab = item }
                )
            }
            Spacer()
        }
        .padding(.horizontal, 48)
        .background(Neon.surfaceBackground.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
    }

    private func count(for tab: DetailTab) -> Int {
        switch tab {
        case .summary:    return meeting.tasks.count
        case .transcript: return meeting.transcript.count
        case .chapters:   return meeting.chapters.count
        }
    }
}

private struct TabButton: View {
    let label: String
    let count: Int
    let active: Bool
    let accent: Color
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.neonBody(13, weight: .medium))
                    .foregroundStyle(active ? Neon.textPrimary : Neon.textTertiary)
                Text("\(count)")
                    .font(.neonMono(10))
                    .foregroundStyle(Neon.textQuaternary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.04)))
            }
            .padding(.vertical, 12)
            .padding(.trailing, 24)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(active ? accent : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}
