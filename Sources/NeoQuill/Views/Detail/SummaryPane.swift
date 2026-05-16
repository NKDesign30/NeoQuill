import SwiftUI

// TLDR (Inter-Lead) + Highlights + Aktionspunkte + Sprechanteil — max 760 wide.

struct SummaryPane: View {
    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            tldrSection
            highlightsSection
            tasksSection
            participantsSection
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private var tldrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TL;DR · WAS GESAGT WURDE").neonEyebrow(accent)
            Text(meeting.tldr)
                .font(.neonAltLead)
                .foregroundStyle(Neon.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WAS WICHTIG WAR").neonEyebrow()
            VStack(spacing: 8) {
                ForEach(meeting.highlights) { h in
                    HighlightRow(highlight: h, accent: accent)
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("AKTIONSPUNKTE").neonEyebrow()
                Spacer()
                let done = meeting.tasks.filter { $0.status == .done }.count
                Text("\(done) / \(meeting.tasks.count) erledigt")
                    .font(.neonBody(11))
                    .foregroundStyle(Neon.textTertiary)
            }

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
                        },
                        onSendToInbox: {
                            sendToInbox(t)
                        }
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEILNEHMER · SPRECHANTEIL").neonEyebrow()
            VStack(spacing: 12) {
                let total = ParticipantBar.parseSpoke(meeting.duration)
                ForEach(meeting.participants) { p in
                    ParticipantBar(participant: p, totalSeconds: total, accent: accent)
                }
            }
        }
    }

    private func sendToInbox(_ item: ActionItem) {
        let appState = state
        let meeting = meeting
        Task { @MainActor in
            do {
                _ = try await MeetingInboxBridge.sendActionItem(item, from: meeting)
                appState.notify("Aufgabe an Neo Inbox: \(item.task)")
            } catch {
                appState.notify("Inbox-Fehler: \(error.localizedDescription)")
            }
        }
    }
}
