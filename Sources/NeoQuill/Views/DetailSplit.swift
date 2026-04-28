import SwiftUI

// Variant B: 2-Column. Transcript links · Sticky Summary-Rail rechts (360w).

struct DetailSplit: View {
    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary

    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(title: meeting.title, meeting: meeting)
            HStack(spacing: 0) {
                transcript
                Rectangle().fill(Neon.strokeHairline).frame(width: Neon.hairlineWidth)
                summaryRail
                    .frame(width: 360)
            }
            AudioPlayer(accent: accent)
        }
    }

    private var transcript: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("· \(meeting.platform.rawValue) · \(meeting.dateLong)")
                        .neonEyebrow(accent)
                }
                Text(meeting.title)
                    .font(.neonDisplay(28))
                    .foregroundStyle(Neon.textPrimary)
                    .padding(.bottom, 4)

                ForEach(meeting.transcript) { line in
                    SplitTranscriptRow(line: line, meeting: meeting, accent: accent)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                tldr
                stats
                highlights
                tasks
                participants
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(Color.white.opacity(0.02))
    }

    private var tldr: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TL;DR").neonEyebrow(accent)
            Text(meeting.tldr)
                .font(.neonBody(14))
                .foregroundStyle(Neon.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                RailStat(label: "Dauer",      value: meeting.duration)
                RailStat(label: "Wörter",     value: "\(meeting.wordCount)")
                RailStat(label: "Teilnehmer", value: "\(meeting.participantCount)")
                RailStat(label: "Tasks",      value: "\(meeting.openTasks) offen", accent: accent)
            }
        }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
            Text("HIGHLIGHTS").neonEyebrow()
            VStack(spacing: 6) {
                ForEach(meeting.highlights) { h in
                    HighlightRow(highlight: h, accent: accent)
                }
            }
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
            Text("AKTIONSPUNKTE").neonEyebrow()
            VStack(spacing: 0) {
                ForEach(Array(meeting.tasks.enumerated()), id: \.element.id) { idx, t in
                    TaskRow(
                        task: t,
                        participants: meeting.participants,
                        accent: accent,
                        isLast: idx == meeting.tasks.count - 1,
                        onToggle: {
                            let next: TaskStatus = t.status == .done ? .open : .done
                            state.store.updateTaskStatus(meetingId: meeting.id, taskId: t.id, status: next)
                        }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var participants: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
            Text("SPRECHANTEIL").neonEyebrow()
            VStack(spacing: 12) {
                let total = ParticipantBar.parseSpoke(meeting.duration)
                ForEach(meeting.participants) { p in
                    ParticipantBar(participant: p, totalSeconds: total, accent: accent)
                }
            }
        }
    }
}

private struct RailStat: View {
    let label: String
    let value: String
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).neonEyebrow()
            Text(value)
                .font(.neonDisplay(22))
                .foregroundStyle(accent ?? Neon.textPrimary)
        }
    }
}

private struct SplitTranscriptRow: View {
    let line: TranscriptLine
    let meeting: MeetingDetail
    let accent: Color

    private var participant: Participant? {
        meeting.participants.first(where: { $0.id == line.who })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let p = participant {
                Avatar(initials: p.id, color: p.color, size: 26)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(participant?.name ?? line.who)
                        .font(.neonBody(12, weight: .medium))
                        .foregroundStyle(Neon.textPrimary)
                    Text(line.timestamp)
                        .font(.neonMono(10))
                        .foregroundStyle(Neon.textTertiary)
                }
                if line.highlight {
                    Text(line.body)
                        .font(.neonBody(13))
                        .foregroundStyle(Neon.textPrimary)
                        .lineSpacing(2)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(accent).frame(width: 2)
                        }
                } else {
                    Text(line.body)
                        .font(.neonBody(13))
                        .foregroundStyle(Neon.textSecondary)
                        .lineSpacing(2)
                }
            }
        }
    }
}
