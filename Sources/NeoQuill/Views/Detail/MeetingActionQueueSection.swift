import SwiftUI

struct MeetingActionQueueSection: View {
    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary
    @EnvironmentObject private var state: AppState
    @AppStorage(AppSettings.actionNeoSkillBridgeEnabled) private var neoSkillBridgeEnabled: Bool

    private var actions: [MeetingAction] {
        MeetingActionGenerator.suggest(for: meeting)
    }

    var body: some View {
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("VORGESCHLAGENE AKTIONEN").neonEyebrow(accent)
                    Spacer()
                    Text("\(actions.count) Vorschläge")
                        .font(.neonBody(11))
                        .foregroundStyle(Neon.textTertiary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        MeetingActionRow(
                            action: action,
                            accent: accent,
                            isLast: index == actions.count - 1,
                            executeLabel: neoSkillBridgeEnabled ? "An Inbox senden" : action.kind.actionLabel,
                            onExecute: { execute(action) }
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
    }

    private func execute(_ action: MeetingAction) {
        let meeting = meeting
        Task { @MainActor in
            do {
                if neoSkillBridgeEnabled {
                    _ = try await MeetingInboxBridge.sendMeetingAction(action, from: meeting)
                    state.notify("An Action-Inbox gesendet: \(action.kind.displayName)")
                } else {
                    let result = try MeetingActionExecutor.execute(action, meeting: meeting)
                    state.notify(result.message)
                }
            } catch {
                state.notify("Aktion fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }
}

private struct MeetingActionRow: View {
    let action: MeetingAction
    var accent: Color
    var isLast: Bool
    var executeLabel: String
    var onExecute: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(action.kind.displayName.uppercased())
                .font(.neonMono(9, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(width: 106)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(accent.opacity(0.10)))

            VStack(alignment: .leading, spacing: 5) {
                Text(action.title)
                    .font(.neonBody(14, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(action.summary)
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("CONF \(Int(action.confidence * 100))%")
                    if !action.due.isEmpty {
                        Text("·")
                        Text(action.due.uppercased())
                    }
                }
                .font(.neonMono(10))
                .tracking(0.4)
                .foregroundStyle(Neon.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(executeLabel, action: onExecute)
                .font(.neonBody(12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(0.82))
                )
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
            }
        }
    }
}
