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
    @State private var showImportSheet = false
    @StateObject private var playback = AudioPlaybackController()
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: meeting.title, meeting: meeting)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HeaderHero(meeting: meeting, accent: accent)
                    if hasOnlyAnonymousSpeakers {
                        anonymousSpeakerBanner
                    }
                    tabsBar
                    Group {
                        switch tab {
                        case .summary:    SummaryPane(meeting: meeting, accent: accent)
                        case .transcript: TranscriptPane(meeting: meeting, query: $state.query, accent: accent)
                        case .chapters:   ChaptersPane(meeting: meeting, accent: accent, playback: playback)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 28)
                    .padding(.bottom, 48)
                }
            }

            AudioPlayer(
                totalSeconds: SpokenDuration.seconds(from: meeting.duration) ?? 0,
                audioURL: meeting.audioURL,
                accent: accent,
                waveformSeed: abs(meeting.id.hashValue) % 9999,
                playback: playback
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            TransientNoticeBanner()
                .animation(.easeInOut(duration: 0.25), value: state.transientNotice)
        }
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
            transcriptStatusPill
        }
        .padding(.horizontal, 48)
        .background(Neon.surfaceBackground.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
    }

    @ViewBuilder
    private var transcriptStatusPill: some View {
        if meeting.processing {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                Text("Finalisiert")
                    .font(.neonMono(10, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(accent.opacity(0.10)))
        } else if !meeting.transcript.isEmpty {
            HStack(spacing: 6) {
                GlyphView(name: .checkCircle, size: 11, color: accent)
                Text("Final")
                    .font(.neonMono(10, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(accent.opacity(0.10)))
        }
    }

    private var hasOnlyAnonymousSpeakers: Bool {
        let anonymousIds: Set<String> = ["S1", "S2", "S3", "S4"]
        let nonLocal = meeting.participants.filter { !LocalSpeakerProfile.isLocalSpeakerId($0.id) }
        guard !nonLocal.isEmpty else { return false }
        return nonLocal.allSatisfy { anonymousIds.contains($0.id) }
    }

    @ViewBuilder
    private var anonymousSpeakerBanner: some View {
        HStack(spacing: 12) {
            GlyphView(name: .download, size: 14, color: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Echte Speaker-Namen importieren?")
                    .font(.neonBody(13, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                Text("Wenn du das offizielle Teams/Meet/Zoom-Transkript hast, ersetzen wir S1/S2 durch echte Namen.")
                    .font(.neonBody(11))
                    .foregroundStyle(Neon.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Transkript wählen") { showImportSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 12)
        .background(accent.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent.opacity(0.18)).frame(height: 1)
        }
        .sheet(isPresented: $showImportSheet) {
            ImportTranscriptSheet(meetingId: meeting.id, meetingTitle: meeting.title) { _ in
                showImportSheet = false
            }
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
